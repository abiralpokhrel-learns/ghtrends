"""
Smoke test for the numpy vector index.

Loads vectors.npy and repos.parquet from S3, encodes a test query,
runs cosine similarity, prints top 10 neighbors. Use this to sanity-check
the index before deploying Streamlit.

Run:
    export EMBEDDINGS_BUCKET=ghtrends-dev-lake
    export AWS_PROFILE=ghtrends
    python test_search.py "data engineering python pipelines"
"""
from __future__ import annotations

import io
import os
import sys

import boto3
import numpy as np
import pandas as pd
from sentence_transformers import SentenceTransformer

EMBEDDINGS_BUCKET = os.environ["EMBEDDINGS_BUCKET"]


def load_index():
    s3 = boto3.client("s3")
    v = s3.get_object(Bucket=EMBEDDINGS_BUCKET, Key="embeddings/v1/vectors.npy")["Body"].read()
    m = s3.get_object(Bucket=EMBEDDINGS_BUCKET, Key="embeddings/v1/repos.parquet")["Body"].read()
    vectors = np.load(io.BytesIO(v))
    metadata = pd.read_parquet(io.BytesIO(m))
    # L2-normalize so dot product == cosine similarity.
    norms = np.linalg.norm(vectors, axis=1, keepdims=True)
    vectors = vectors / np.where(norms == 0, 1, norms)
    return vectors, metadata


def search(query: str, k: int = 10):
    vectors, metadata = load_index()
    if len(vectors) == 0:
        return metadata.copy()
    k = min(k, len(vectors))
    model = SentenceTransformer("sentence-transformers/all-MiniLM-L6-v2")
    qv = model.encode(query)
    qv = qv / (np.linalg.norm(qv) or 1)
    sims = vectors @ qv
    top_idx = np.argpartition(sims, -k)[-k:]
    top_idx = top_idx[np.argsort(-sims[top_idx])]
    results = metadata.iloc[top_idx].copy()
    results["similarity"] = sims[top_idx]
    return results


if __name__ == "__main__":
    query = " ".join(sys.argv[1:]) or "data engineering python pipelines"
    print(f"Query: {query!r}\n")
    df = search(query)
    print(df[["full_name", "language", "stars", "similarity"]].to_string(index=False))
