"""
Semantic search page.

Loads precomputed embeddings (numpy + parquet) from S3 once at startup,
caches in memory. At query time: encode the query with sentence-transformers,
run cosine similarity in numpy, return top-K. No vector database. No backend
service. ~1 ms per search after the model is loaded.
"""
import io
import os

import boto3
import numpy as np
import pandas as pd
import streamlit as st
from sentence_transformers import SentenceTransformer

EMBEDDINGS_BUCKET = os.environ["EMBEDDINGS_BUCKET"]
S3_KEY_VECTORS    = "embeddings/v1/vectors.npy"
S3_KEY_METADATA   = "embeddings/v1/repos.parquet"
MODEL_NAME        = "sentence-transformers/all-MiniLM-L6-v2"

st.title("Semantic Repo Search")


@st.cache_resource
def load_model():
    """Load sentence-transformers once. ~30 seconds cold start on Streamlit Cloud."""
    return SentenceTransformer(MODEL_NAME)


@st.cache_data(ttl=86400)  # refresh once a day
def load_index():
    """Pull vectors.npy and repos.parquet from S3, normalize for cosine sim."""
    s3 = boto3.client("s3")
    v = s3.get_object(Bucket=EMBEDDINGS_BUCKET, Key=S3_KEY_VECTORS)["Body"].read()
    m = s3.get_object(Bucket=EMBEDDINGS_BUCKET, Key=S3_KEY_METADATA)["Body"].read()
    vectors = np.load(io.BytesIO(v)).astype(np.float32)
    metadata = pd.read_parquet(io.BytesIO(m))
    # L2-normalize so dot product equals cosine similarity.
    norms = np.linalg.norm(vectors, axis=1, keepdims=True)
    vectors = vectors / np.where(norms == 0, 1, norms)
    return vectors, metadata


def search(query: str, k: int = 10) -> pd.DataFrame:
    model = load_model()
    vectors, metadata = load_index()
    if len(vectors) == 0:
        return metadata.copy()
    k = min(k, len(vectors))
    qv = model.encode(query).astype(np.float32)
    qv = qv / (np.linalg.norm(qv) or 1)
    sims = vectors @ qv
    top_idx = np.argpartition(sims, -k)[-k:]
    top_idx = top_idx[np.argsort(-sims[top_idx])]
    results = metadata.iloc[top_idx].copy()
    results["similarity"] = sims[top_idx]
    return results


query_text = st.text_input(
    "Describe what you're looking for",
    placeholder="e.g. data engineering pipelines in python with airflow",
)

if query_text:
    with st.spinner("Searching..."):
        results = search(query_text, k=10)
    for _, r in results.iterrows():
        full_name = r["full_name"]
        lang = r.get("language") or "Unknown"
        stars = int(r.get("stars") or 0)
        st.markdown(
            f"**[{full_name}](https://github.com/{abiralpokhrel-learns})** "
            f"— {lang} — :star: {stars:,}"
        )
        st.caption(f"Similarity: {r['similarity']:.3f}")
        st.write(r.get("description") or "_no description_")
        st.divider()

with st.sidebar:
    st.caption(
        "Embeddings are precomputed offline with "
        "sentence-transformers/all-MiniLM-L6-v2 and stored as a numpy file "
        "in S3. Search runs as an in-memory dot product — no vector database."
    )
