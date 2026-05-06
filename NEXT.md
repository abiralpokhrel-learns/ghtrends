# v2 ideas — do NOT start these until v1 is shipped

This file exists for one reason: to give you a place to write down "I should add X" without actually adding it. v1 ships first.

Each idea includes:
- What it is
- Why it was cut from v1
- When it would be worth adding
- Rough effort

---

## Apache Iceberg lakehouse

**What:** Replace plain Parquet + Glue Crawler with Iceberg tables managed via Athena DDL.

**Why cut:** For append-only event data with date partitions, plain Parquet gives 80% of the resume value at 20% of the complexity. Iceberg's killer features (time travel, schema evolution, ACID) are not needed here.

**Add when:** You want a real lakehouse on the resume *and* you have a use case for time-travel queries (e.g. "what was the top repo as-of last Monday?").

**Effort:** ~14 hours.

---

## Step Functions orchestration

**What:** Replace EventBridge → Lambda direct invocation with a Step Functions state machine that handles ingest + Iceberg load + dbt build + retry logic.

**Why cut:** For hourly batch ingest, Step Functions adds complexity without meaningful reliability gain. EventBridge → Lambda with Lambda's built-in retries is enough.

**Add when:** You add multi-step pipelines (ingest → transform → validate → publish) where each step can fail independently.

**Effort:** ~8 hours.

---

## pgvector + Postgres

**What:** Postgres + pgvector extension running in Docker on EC2 (or RDS) to power vector search.

**Why cut:** For 500-1000 vectors at 384 dims, numpy in-memory cosine similarity is faster than pgvector and has zero infrastructure. The break-even point for pgvector is ~100K vectors.

**Add when:** Your embedding count crosses ~100K, or you need transactional updates to vectors.

**Effort:** ~14 hours.

---

## Self-hosted EC2 worker

**What:** Run dbt, embeddings, and Streamlit on a t3.micro EC2 with nginx + Let's Encrypt.

**Why cut:** Streamlit Community Cloud is free, always-on, and managed. GitHub Actions handles dbt scheduling. There's nothing left for EC2 to do at v1 scale.

**Add when:** You outgrow Streamlit Cloud's 1 GB RAM limit, or you need long-running processes that GitHub Actions won't cover.

**Effort:** ~12 hours including TLS setup.

---

## GitHub Actions OIDC role hardening

**What:** Replace the broad `AdministratorAccess` policy on the OIDC role with narrowly-scoped policies (S3, Glue, Athena, Lambda only).

**Why cut:** Tedious work that doesn't ship a feature. Worth doing for a real production system, not for a v1 portfolio.

**Add when:** You're using this codebase as a template for a real production system, or you want to demonstrate IAM expertise.

**Effort:** ~4 hours.

---

## Real-time streaming via Kinesis

**What:** Replace hourly batch with Kinesis Data Streams + Lambda consumer for sub-minute latency.

**Why cut:** GitHub Archive itself is hourly batch. There's no upstream stream to consume. Adding Kinesis here would be a fake demo.

**Add when:** You switch to a different data source that actually streams (e.g. Twitter firehose, Slack events).

**Effort:** ~20 hours.

---

## LLM-powered RAG over repo READMEs

**What:** Fetch repo READMEs, chunk them, embed each chunk, build a RAG pipeline that answers questions like "which repos use Polars and DuckDB together?"

**Why cut:** Adds a dependency on either OpenAI (paid) or a self-hosted LLM (expensive). Not differentiated enough to justify the cost.

**Add when:** You want to demonstrate RAG-specific skills, or there's a clear use case beyond demo.

**Effort:** ~30 hours.

---

## More dbt marts

**What:** Add `dim_repos`, `fct_org_activity_daily`, `dim_languages`, etc.

**Why cut:** One mart, queried multiple ways from the dashboard, demonstrates the dbt skill enough for v1.

**Add when:** Specific dashboard pages would be cleaner with their own mart.

**Effort:** 2-3 hours per additional mart.

---

## Schema enforcement and contract tests

**What:** Add `Great Expectations` or `Soda` for data quality checks beyond what dbt tests cover.

**Why cut:** dbt tests are enough for v1.

**Add when:** You're producing data that downstream teams consume.

**Effort:** ~10 hours.

---

## Cross-region disaster recovery

**What:** Replicate S3 to a second region, IaC for cross-region failover.

**Why cut:** Total over-engineering for a portfolio project.

**Add when:** Never, unless this becomes a real production system.

**Effort:** A lot.

---

## How to use this list

If during v1 you think "I should add X", look here first.

- If X is on this list: write down any new context in the relevant section, but don't act on it.
- If X is not on this list: add it as a new entry with a "why not now" note.

The discipline of writing it down instead of doing it is the whole point.
