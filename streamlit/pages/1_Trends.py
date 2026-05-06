"""Trends page — line charts and tables fed by the dbt mart via Athena."""
import os
from datetime import date, timedelta

import pandas as pd
import streamlit as st
from pyathena import connect

st.title("Trends")

ATHENA_OUTPUT_S3 = os.environ["ATHENA_OUTPUT_S3"]
ATHENA_DB = "ghtrends_lake"


@st.cache_resource
def get_athena_conn():
    return connect(
        s3_staging_dir=ATHENA_OUTPUT_S3,
        region_name="us-east-1",
        schema_name=ATHENA_DB,
    )


@st.cache_data(ttl=3600)
def query(sql: str) -> pd.DataFrame:
    return pd.read_sql(sql, get_athena_conn())


# --- Filters ---
col1, col2 = st.columns([1, 3])
with col1:
    days = st.selectbox("Window", [7, 14, 30, 60], index=2)
start = date.today() - timedelta(days=days)

# --- Top trending repos ---
st.subheader(f"Top trending repos by stars (last {days} days)")
df = query(f"""
    select repo_name, sum(stars) as stars
    from {ATHENA_DB}.fct_repo_trends_daily
    where event_date >= date '{start.isoformat()}'
    group by repo_name
    order by stars desc
    limit 50
""")
st.dataframe(df, use_container_width=True)

# --- Stars over time (top 10) ---
st.subheader("Star velocity — top 10 repos over time")
top_repos = df.head(10)["repo_name"].tolist()
if top_repos:
    in_clause = ",".join(f"'{r}'" for r in top_repos)
    df_ts = query(f"""
        select event_date, repo_name, stars
        from {ATHENA_DB}.fct_repo_trends_daily
        where event_date >= date '{start.isoformat()}'
          and repo_name in ({in_clause})
        order by event_date
    """)
    pivot = df_ts.pivot(index="event_date", columns="repo_name", values="stars").fillna(0)
    st.line_chart(pivot)
