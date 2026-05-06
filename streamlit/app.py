"""
Streamlit dashboard entry point.

Pages live in ./pages/ and Streamlit auto-discovers them in the sidebar.
This file is the landing page.
"""
import streamlit as st

st.set_page_config(
    page_title="GH Trends",
    page_icon=":bar_chart:",
    layout="wide",
)

st.title("Open Source Trends Intelligence")
st.markdown(
    """
    Live trend analysis over the public GitHub Archive.

    Use the sidebar to navigate:

    - **Trends** — daily charts of stars, PRs, languages, organizations
    - **Search** — semantic search over trending repositories
    - **About** — architecture and source code

    Data refreshes every hour.
    """
)

with st.sidebar:
    st.header("About this app")
    st.markdown(
        "Data ingested from [GH Archive](https://www.gharchive.org/), "
        "modeled with dbt-core, served from Athena and a precomputed numpy "
        "vector index in S3."
    )
