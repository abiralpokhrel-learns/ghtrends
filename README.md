# Open Source Trends Intelligence Platform

A serverless data platform on AWS that ingests every public GitHub event, models trends with dbt-core on a Glue + Athena lakehouse, and adds semantic search over trending repositories using sentence-transformers and a numpy vector index. Built end-to-end as a portfolio project demonstrating modern data engineering practices: hourly ingestion via Lambda + EventBridge, partitioned Parquet on S3, version-controlled SQL transformations with dbt, automated cost guardrails, and a public Streamlit demo. Total monthly operating cost: under $2.

## Live demo

**App:** <https://ghtrends.streamlit.app/> (e.g. `https://ghtrends-abiral.streamlit.app`)

**90-second walkthrough:**

[![Demo video](docs/demo_thumbnail.png)](<TODO_LOOM_URL>)

**dbt project documentation:** [abiralpokhrel-learns.github.io/ghtrends](https://abiralpokhrel-learns.github.io/ghtrends/)

> Note on cold start: the app sleeps after 30 minutes of inactivity. First request after sleep takes 30-60 seconds to wake up.

## Screenshot

![Dashboard screenshot](docs/screenshots/trends_page.png)

## Architecture

```mermaid
flowchart LR
    A[GH Archive<br/>data.gharchive.org] --> B[EventBridge<br/>cron 5 * * * ?]
    B --> C[Lambda<br/>ingest function]
    C --> D[(S3 raw<br/>partitioned Parquet)]
    D --> E[Glue Crawler<br/>daily]
    E --> F[Glue Catalog]
    F --> G[Athena<br/>SQL queries]
    F --> H[dbt-core<br/>staging + mart]
    H --> I[(S3 mart<br/>fct_repo_trends_daily)]
    I --> J[Embeddings job<br/>laptop, weekly]
    J --> K[(S3 vector index<br/>vectors.npy)]
    G --> L[Streamlit Cloud<br/>Trends page]
    K --> M[Streamlit Cloud<br/>Search page]
    I --> L
```

The flow in plain English:

- Every hour, EventBridge fires a Lambda function
- The Lambda downloads one hour of public GitHub events, filters to stars and pull requests, and writes Parquet to S3
- A Glue Crawler runs daily, registering new partitions in the Glue Catalog so Athena can query them
- dbt-core runs nightly, transforming the raw events into a `fct_repo_trends_daily` mart
- A weekly batch job picks the top 500 trending repos, embeds their descriptions with sentence-transformers, and uploads a numpy vector index to S3
- Streamlit Cloud reads from Athena (for trends) and from the S3 vector index (for semantic search)

## Tech stack

| Layer | Tool | Why |
|---|---|---|
| Ingestion | AWS Lambda + EventBridge | Pay-per-invocation, no server to maintain |
| Lake storage | Amazon S3, partitioned Parquet | Cheap, query-friendly, 5 GB free for 12 months |
| Catalog | AWS Glue Crawler + Glue Catalog | Auto-discovers new partitions, free tier covers it |
| Query engine | Amazon Athena | Serverless SQL on S3, pay per byte scanned |
| Transformation | dbt-core (Athena adapter) | Version-controlled SQL, dependency graph, testing |
| Embeddings | sentence-transformers (all-MiniLM-L6-v2) | Small (90 MB), fast, runs on a laptop CPU |
| Vector search | numpy in-memory cosine similarity | Sub-millisecond on 500 vectors. Faster than pgvector at this scale and zero infra |
| Vector storage | numpy + parquet on S3 | Streamlit Cloud loads the index at startup |
| UI | Streamlit on Streamlit Community Cloud | Free hosting, auto-deploy from GitHub |
| IaC | Terraform | 100% of infrastructure declared in code |
| State backend | S3 + DynamoDB | Standard production pattern for Terraform state |

## Design notes

A few choices that may surprise people:

- **No vector database.** For ~500 vectors at 384 dims, numpy's in-memory dot product is faster than pgvector and has zero infrastructure to maintain. The break-even point for a vector database is ~100K vectors; we're well below that.
- **No Iceberg.** Plain Parquet partitioned by date is enough for append-only event data. Iceberg's killer features (time travel, schema evolution, ACID) are not needed here. Captured in `NEXT.md` as a v2 idea.
- **No EC2.** Streamlit Community Cloud handles hosting for free. Embeddings are computed once a week on a laptop and pushed to S3. There is no always-on compute in this project.
- **No Step Functions.** EventBridge → Lambda direct invocation handles hourly batch ingest reliably. Step Functions would add complexity without proportional reliability gain at this scale.
- **No GitHub Actions for dbt yet.** dbt runs are manual for v1 (one command). OIDC + Actions cron is a v2 task. The dbt code is identical regardless of how it's scheduled.

The full reasoning for each cut is in `NEXT.md`.

## Findings

Five real findings produced by the queries in `analysis/queries/`:

### 1. <TODO_FINDING_1_HEADLINE>

![Finding 1](analysis/findings/01_top_starred_repos.png)

<TODO_FINDING_1_PARAGRAPH>

Query: [`analysis/queries/01_top_starred_repos.sql`](analysis/queries/01_top_starred_repos.sql)

### 2. <TODO_FINDING_2_HEADLINE>

![Finding 2](analysis/findings/02_star_velocity.png)

<TODO_FINDING_2_PARAGRAPH>

Query: [`analysis/queries/02_star_velocity.sql`](analysis/queries/02_star_velocity.sql)

### 3. <TODO_FINDING_3_HEADLINE>

![Finding 3](analysis/findings/03_pr_merge_rate.png)

<TODO_FINDING_3_PARAGRAPH>

Query: [`analysis/queries/03_pr_merge_rate.sql`](analysis/queries/03_pr_merge_rate.sql)

### 4. <TODO_FINDING_4_HEADLINE>

![Finding 4](analysis/findings/06_hourly_star_distribution.png)

<TODO_FINDING_4_PARAGRAPH>

Query: [`analysis/queries/06_hourly_star_distribution.sql`](analysis/queries/06_hourly_star_distribution.sql)

### 5. <TODO_FINDING_5_HEADLINE>

![Finding 5](analysis/findings/04_top_organizations.png)

<TODO_FINDING_5_PARAGRAPH>

Query: [`analysis/queries/04_top_organizations.sql`](analysis/queries/04_top_organizations.sql)

## Cost breakdown

Designed to stay within the AWS free tier. Real spend during development:

| Service | Free tier (months 1-12) | After free tier (month 13+) |
|---|---|---|
| S3 storage | $0 (under 5 GB) | ~$0.10 |
| Lambda invocations | $0 (under 1M/month) | $0 |
| Athena scans | $0.50 (with 1 GB/query cap) | $0.50 |
| Glue Crawler | $0 (under 1M DPU-hours) | $0 |
| EventBridge | $0 | $0 |
| Streamlit Community Cloud | $0 (free forever for public apps) | $0 |
| **Total** | **$0-1/month** | **~$1-2/month** |

## Local setup

Reproduces the dev environment if you want to run any of this yourself.

```bash
# Clone
git clone https://github.com/abiralpokhrel-learns/ghtrends.git
cd ghtrends

# AWS account setup
# (creates S3 state bucket + DynamoDB lock table)
make bootstrap

# Configure backend
# Edit terraform/backend.tf with the bucket name printed by bootstrap
# Add TFSTATE_BUCKET=<name> to .env

# Provision infra
make tf-init
make tf-apply

# Build the ingest Lambda zip
make lambda-package

# Run the Glue Crawler manually for the first time
aws glue start-crawler --name ghtrends-dev-crawler --profile ghtrends

# Run the dbt models
cd dbt
dbt deps
dbt build

# Build the embeddings index (top 500 trending repos)
cd ../embeddings
python -m venv venv && source venv/Scripts/activate
pip install -r requirements.txt
python embed_repos.py --top 500

# Run Streamlit locally
cd ../streamlit
python -m venv venv && source venv/Scripts/activate
pip install -r requirements.txt
streamlit run app.py
```

Required local tools: Python 3.11+, Terraform 1.6+, AWS CLI v2, Docker (for Lambda packaging), Git, Make.

You will need an AWS account, a GitHub Personal Access Token (no scopes needed), and ~3 hours of patience for first-time setup. Total infra cost under $2/month.

## Project structure

```
ghtrends/
├── PHASES.md                    # Detailed 6-phase build plan
├── NEXT.md                      # v2 ideas (cut from v1)
├── README.md                    # This file
├── Makefile                     # Common commands
├── bootstrap/                   # One-time scripts (state backend)
├── terraform/                   # All infra as code
│   └── modules/
│       ├── s3_data_lake/        # Two S3 buckets
│       ├── lambda_ingest/       # Lambda + EventBridge
│       ├── glue_catalog/        # Glue Catalog + Crawler
│       └── streamlit_reader/    # Read-only IAM user for Streamlit Cloud
├── lambda/
│   └── ingest_gh_archive/       # Hourly ingest function
├── dbt/
│   └── models/
│       ├── staging/             # Clean column types
│       ├── intermediate/        # Daily aggregates
│       └── marts/               # fct_repo_trends_daily
├── embeddings/                  # Offline numpy vector index builder
├── streamlit/                   # Dashboard + semantic search
│   └── pages/
├── analysis/queries/            # Raw Athena SQL for ad-hoc analysis
└── docs/                        # Findings, screenshots, diagrams
```

## What this project is NOT

- Not a real-time streaming pipeline. GitHub Archive is hourly batch.
- Not a managed lakehouse with Iceberg. Plain Parquet, by design.
- Not a recommendation engine. The vector search is for finding similar repos by description, nothing more.
- Not enterprise-grade. The IAM is admin-level for the build user. v2 would tighten this.

Constraints I held to: every component is in the AWS free tier (or free forever), the architecture is reproducible from a clean AWS account in under a day, and every choice is defensible in an interview.

## Built by

Abiral Pokhrel — [GitHub](https://github.com/abiralpokhrel-learns) • [LinkedIn](https://www.linkedin.com/in/abiralpokhrel2005/)

Reach out if you'd like to talk about data engineering, AWS, or this project specifically.

## License

MIT — see [LICENSE](LICENSE) file.
