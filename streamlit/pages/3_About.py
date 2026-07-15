"""About page — architecture, links, contact."""
import streamlit as st

st.title("About this project")

st.markdown(
    """
    ### What this is

    A serverless data platform on AWS that ingests public GitHub Archive events,
    models trends with dbt-core, and adds semantic search over trending
    repositories using sentence-transformers and a numpy vector index.

    ### Stack

    | Layer | Tool |
    |---|---|
    | Ingestion | AWS Lambda + EventBridge |
    | Lake storage | Amazon S3, partitioned Parquet |
    | Catalog | AWS Glue Crawler + Glue Catalog |
    | Query | Amazon Athena |
    | Modeling | dbt-core (single trend mart) |
    | Embeddings | sentence-transformers (all-MiniLM-L6-v2) |
    | Vector search | numpy in-memory cosine similarity |
    | Vector storage | numpy + parquet in S3 |
    | UI | Streamlit on Streamlit Community Cloud |
    | IaC | Terraform |
    | CI/CD | GitHub Actions |

    ### Design notes

    - **No vector database.** For ~500 vectors at 384 dims, a numpy dot product
      is faster than pgvector and has zero infrastructure to run.
    - **No EC2.** Streamlit Community Cloud handles hosting for free. Embeddings
      are computed offline on a laptop and pushed to S3.
    - **No Iceberg.** Plain partitioned Parquet with a Glue Crawler is enough
      for append-only event data.

    ### Source

    [github.com/YOUR_USERNAME/ghtrends](https://github.com/abiralpokhrel-learns/ghtrends)

    ### Contact

    Built by NISHANT PANDEY.
    """
)
