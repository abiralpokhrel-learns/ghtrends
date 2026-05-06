"""
Offline embedding job. Run on your laptop once a week.

Pulls top-N trending repos from the dbt mart via Athena, enriches with
GitHub API descriptions, embeds with sentence-transformers, and saves to S3:

    s3://<bucket>/embeddings/v1/vectors.npy   shape: (N, 384)
    s3://<bucket>/embeddings/v1/repos.parquet metadata aligned by row index

The Streamlit app loads both files at startup and runs cosine similarity
in numpy. No vector database. No service to babysit.

Resumable: if S3 already has files, we skip repos already embedded
and append the rest.

Usage:
    export ATHENA_OUTPUT_S3=s3://ghtrends-dev-lake/athena_results/
    export EMBEDDINGS_BUCKET=ghtrends-dev-lake
    export GITHUB_PAT=...
    export AWS_PROFILE=ghtrends
    python embed_repos.py --top 500
"""
from __future__ import annotations

import argparse
import io
import logging
import os
import time
from typing import Iterator

import boto3
import numpy as np
import pandas as pd
import requests
from sentence_transformers import SentenceTransformer

# --- Config ---
ATHENA_DATABASE   = "ghtrends_lake"
ATHENA_OUTPUT_S3  = os.environ["ATHENA_OUTPUT_S3"]
GITHUB_PAT        = os.environ["GITHUB_PAT"]
EMBEDDINGS_BUCKET = os.environ["EMBEDDINGS_BUCKET"]
S3_KEY_VECTORS    = "embeddings/v1/vectors.npy"
S3_KEY_METADATA   = "embeddings/v1/repos.parquet"
MODEL_NAME        = "sentence-transformers/all-MiniLM-L6-v2"
EMBED_DIM         = 384

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger(__name__)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--top", type=int, default=500, help="How many top repos to embed")
    args = parser.parse_args()

    log.info("Loading model %s ...", MODEL_NAME)
    model = SentenceTransformer(MODEL_NAME)

    log.info("Querying top %d trending repos from Athena ...", args.top)
    repos = list(_top_repos_via_athena(args.top))
    log.info("Got %d repos from Athena", len(repos))

    log.info("Loading existing index from S3 (if any) ...")
    existing_vecs, existing_meta = _load_existing_index()
    done_ids = set(existing_meta["repo_id"]) if existing_meta is not None else set()
    log.info("%d repos already embedded; %d new to process", len(done_ids), len(repos) - len(done_ids))

    todo = [r for r in repos if r["repo_id"] not in done_ids]
    if not todo:
        log.info("Nothing to do.")
        return

    log.info("Enriching %d repos via GitHub API ...", len(todo))
    enriched = list(_enrich_with_github_api(todo))
    log.info("%d repos enriched (skipped %d 404s/rate-limits)",
             len(enriched), len(todo) - len(enriched))

    log.info("Encoding %d descriptions ...", len(enriched))
    texts = [(r["description"] or r["full_name"]) for r in enriched]
    new_vecs = model.encode(texts, batch_size=32, show_progress_bar=True)
    new_meta = pd.DataFrame(enriched)

    if existing_vecs is None:
        all_vecs = new_vecs
        all_meta = new_meta
    else:
        all_vecs = np.vstack([existing_vecs, new_vecs])
        all_meta = pd.concat([existing_meta, new_meta], ignore_index=True)

    log.info("Saving %d vectors to S3 ...", len(all_vecs))
    _save_index(all_vecs, all_meta)

    log.info("Done. Index size: %d repos, %.1f MB", len(all_vecs), all_vecs.nbytes / 1e6)


# ---------- Athena ----------

def _top_repos_via_athena(top_n: int) -> Iterator[dict]:
    sql = f"""
        SELECT repo_id, repo_name AS full_name, SUM(stars) AS total_stars
        FROM {ATHENA_DATABASE}.fct_repo_trends_daily
        WHERE event_date >= current_date - interval '30' day
        GROUP BY repo_id, repo_name
        ORDER BY total_stars DESC
        LIMIT {top_n}
    """
    athena = boto3.client("athena", region_name="us-east-1")
    qid = athena.start_query_execution(
        QueryString=sql,
        ResultConfiguration={"OutputLocation": ATHENA_OUTPUT_S3},
    )["QueryExecutionId"]

    while True:
        state = athena.get_query_execution(QueryExecutionId=qid)["QueryExecution"]["Status"]["State"]
        if state == "SUCCEEDED":
            break
        if state in ("FAILED", "CANCELLED"):
            raise RuntimeError(f"Athena query {qid} ended in state {state}")
        time.sleep(1)

    paginator = athena.get_paginator("get_query_results")
    first = True
    for page in paginator.paginate(QueryExecutionId=qid):
        for row in page["ResultSet"]["Rows"]:
            if first:
                first = False
                continue
            cells = [c.get("VarCharValue") for c in row["Data"]]
            yield {"repo_id": int(cells[0]), "full_name": cells[1], "stars": int(cells[2])}


# ---------- GitHub API enrichment ----------

def _enrich_with_github_api(repos: list[dict]) -> Iterator[dict]:
    headers = {
        "Authorization": f"Bearer {GITHUB_PAT}",
        "Accept": "application/vnd.github+json",
    }
    for r in repos:
        url = f"https://api.github.com/repos/{r['full_name']}"
        resp = requests.get(url, headers=headers, timeout=15)

        if resp.status_code == 404:
            log.warning("Not found: %s", r["full_name"])
            continue
        if resp.status_code == 403 and "rate limit" in resp.text.lower():
            reset = int(resp.headers.get("x-ratelimit-reset", time.time() + 60))
            wait = max(reset - int(time.time()), 1) + 1
            log.warning("Rate limited. Sleeping %ds", wait)
            time.sleep(wait)
            continue
        resp.raise_for_status()

        data = resp.json()
        yield {
            "repo_id": r["repo_id"],
            "full_name": r["full_name"],
            "description": data.get("description"),
            "language": data.get("language"),
            "stars": data.get("stargazers_count"),
        }


# ---------- S3 index I/O ----------

def _load_existing_index() -> tuple[np.ndarray | None, pd.DataFrame | None]:
    s3 = boto3.client("s3")
    try:
        v_obj = s3.get_object(Bucket=EMBEDDINGS_BUCKET, Key=S3_KEY_VECTORS)
        m_obj = s3.get_object(Bucket=EMBEDDINGS_BUCKET, Key=S3_KEY_METADATA)
    except s3.exceptions.NoSuchKey:
        return None, None
    except Exception as e:
        if "NoSuchKey" in str(e) or "404" in str(e):
            return None, None
        raise

    vecs = np.load(io.BytesIO(v_obj["Body"].read()))
    meta = pd.read_parquet(io.BytesIO(m_obj["Body"].read()))
    return vecs, meta


def _save_index(vectors: np.ndarray, metadata: pd.DataFrame) -> None:
    s3 = boto3.client("s3")

    v_buf = io.BytesIO()
    np.save(v_buf, vectors)
    v_buf.seek(0)
    s3.put_object(Bucket=EMBEDDINGS_BUCKET, Key=S3_KEY_VECTORS, Body=v_buf.getvalue())

    m_buf = io.BytesIO()
    metadata.to_parquet(m_buf, index=False)
    m_buf.seek(0)
    s3.put_object(Bucket=EMBEDDINGS_BUCKET, Key=S3_KEY_METADATA, Body=m_buf.getvalue())


if __name__ == "__main__":
    main()
