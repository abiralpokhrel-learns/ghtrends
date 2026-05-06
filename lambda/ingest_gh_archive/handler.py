"""
Hourly GitHub Archive ingest Lambda.

Triggered by EventBridge once per hour. Downloads the previous hour's
GH Archive file, filters to event types we care about, writes Parquet
to S3 partitioned by event_type / year / month / day / hour.

Event input shape:
    { "timestamp": "2026-04-01T13:00:00Z" }

If timestamp is missing, defaults to (now - 2 hours) UTC, rounded down to the hour.
GH Archive uploads have a slight lag, so we always pull "previous hour" not "current".

Filtered event types (keep this list small to control storage cost):
    - WatchEvent        (someone starred a repo)
    - PullRequestEvent  (PR opened, closed, merged)
"""
from __future__ import annotations

import gzip
import io
import json
import logging
import os
from datetime import datetime, timedelta, timezone
from typing import Iterator

import boto3
import pyarrow as pa
import pyarrow.parquet as pq
import requests
from botocore.exceptions import ClientError

# --- Config (from Lambda env vars) ---
RAW_BUCKET = os.environ["RAW_BUCKET"]
KEPT_EVENT_TYPES = {"WatchEvent", "PullRequestEvent"}
GH_ARCHIVE_BASE = "https://data.gharchive.org"
HTTP_TIMEOUT_SEC = 60
MAX_RETRIES = 3

s3 = boto3.client("s3")
log = logging.getLogger()
log.setLevel(logging.INFO)


def lambda_handler(event, context):
    """Entry point. See module docstring for expected event shape."""
    target_dt = _resolve_target_hour(event)
    log.info("Ingesting GH Archive for hour=%s", target_dt.isoformat())

    archive_name = f"{target_dt:%Y-%m-%d}-{target_dt.hour}.json.gz"
    url = f"{GH_ARCHIVE_BASE}/{archive_name}"
    raw_bytes = _download_with_retry(url)

    counts = {"total": 0}
    for event_type in KEPT_EVENT_TYPES:
        counts[event_type] = 0

    # Group filtered events by event_type so we can write one Parquet file each.
    buckets = {et: [] for et in KEPT_EVENT_TYPES}
    for evt in _iter_events(raw_bytes):
        counts["total"] += 1
        et = evt.get("type")
        if et in KEPT_EVENT_TYPES:
            buckets[et].append(_flatten(evt))
            counts[et] += 1

    for event_type, rows in buckets.items():
        if not rows:
            continue
        _write_parquet(rows, event_type, target_dt)

    log.info("Done. counts=%s", counts)
    return {"statusCode": 200, "counts": counts, "hour": target_dt.isoformat()}


def _resolve_target_hour(event) -> datetime:
    """Get the hour to ingest. Either from event.timestamp or now-2h."""
    if isinstance(event, dict) and event.get("timestamp"):
        dt = datetime.fromisoformat(event["timestamp"].replace("Z", "+00:00"))
    else:
        dt = datetime.now(timezone.utc) - timedelta(hours=2)
    return dt.astimezone(timezone.utc).replace(minute=0, second=0, microsecond=0)


def _download_with_retry(url: str) -> bytes:
    """Download a gzipped JSON file from GH Archive with backoff."""
    last_err = None
    for attempt in range(1, MAX_RETRIES + 1):
        try:
            log.info("GET %s (attempt %d)", url, attempt)
            r = requests.get(url, timeout=HTTP_TIMEOUT_SEC)
            if r.status_code == 200:
                return r.content
            if r.status_code == 404:
                # GH Archive might not have published yet. Surface clearly.
                raise FileNotFoundError(f"GH Archive 404 for {url}")
            r.raise_for_status()
        except Exception as e:
            last_err = e
            log.warning("Attempt %d failed: %s", attempt, e)
    raise RuntimeError(f"Download failed after {MAX_RETRIES} attempts: {last_err}")


def _iter_events(gz_bytes: bytes) -> Iterator[dict]:
    """Stream-decompress the gzipped JSON-lines file."""
    with gzip.GzipFile(fileobj=io.BytesIO(gz_bytes)) as gz:
        for line in gz:
            try:
                yield json.loads(line)
            except json.JSONDecodeError:
                # GH Archive occasionally has malformed lines. Skip.
                continue


def _flatten(evt: dict) -> dict:
    """Project nested fields to flat columns we'll actually query.

    Keep this conservative — adding columns later is cheap (the Glue Crawler
    will re-detect new fields on its next run); storing useless columns now
    wastes S3 space.
    """
    actor = evt.get("actor") or {}
    repo = evt.get("repo") or {}
    payload = evt.get("payload") or {}
    pr = payload.get("pull_request") or {}

    return {
        "id": evt.get("id"),
        "type": evt.get("type"),
        "actor_id": actor.get("id"),
        "actor_login": actor.get("login"),
        "repo_id": repo.get("id"),
        "repo_name": repo.get("name"),
        "created_at": evt.get("created_at"),
        # PR-specific fields. Will be None for WatchEvent.
        "pr_action": payload.get("action"),
        "pr_merged": pr.get("merged"),
        "pr_state": pr.get("state"),
        "pr_base_ref": (pr.get("base") or {}).get("ref"),
        "pr_user_login": (pr.get("user") or {}).get("login"),
    }


def _write_parquet(rows: list[dict], event_type: str, dt: datetime) -> None:
    """Write rows to S3 at the partition path for this hour."""
    key = (
        f"raw/event_type={event_type}/"
        f"year={dt.year}/month={dt.month:02d}/day={dt.day:02d}/hour={dt.hour:02d}/"
        f"data.parquet"
    )
    if _s3_object_exists(key):
        log.info("Skipping existing s3://%s/%s", RAW_BUCKET, key)
        return

    table = pa.Table.from_pylist(rows)
    buf = io.BytesIO()
    pq.write_table(table, buf, compression="snappy")
    buf.seek(0)

    s3.put_object(Bucket=RAW_BUCKET, Key=key, Body=buf.getvalue())
    log.info("Wrote s3://%s/%s (%d rows)", RAW_BUCKET, key, len(rows))


def _s3_object_exists(key: str) -> bool:
    try:
        s3.head_object(Bucket=RAW_BUCKET, Key=key)
        return True
    except ClientError as e:
        code = e.response.get("Error", {}).get("Code")
        if code in {"404", "NoSuchKey", "NotFound"}:
            return False
        raise


# --- Local test entry point ---
# Run:  python handler.py 2026-04-01T13:00:00Z
if __name__ == "__main__":
    import sys
    ts = sys.argv[1] if len(sys.argv) > 1 else None
    print(lambda_handler({"timestamp": ts} if ts else {}, None))
