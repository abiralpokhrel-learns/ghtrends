# Open Source Trends Intelligence Platform

A serverless data platform on AWS that ingests public GitHub Archive events, models trends with dbt-core on partitioned Parquet, and adds semantic search over trending repositories using sentence-transformers + a numpy vector index.

## Status

Currently building. See `PHASES.md` for the build plan. v2 ideas captured in `NEXT.md`.

## High-level architecture

```
GH Archive (gharchive.org)
        |
        v
   EventBridge (hourly cron)
        |
        v
   Lambda (download + filter + write Parquet)
        |
        v
   S3 raw layer (Parquet partitioned by event_type/year/month/day/hour)
        |
        v
   Glue Crawler -> Glue Catalog
        |
        +---> Athena (ad-hoc SQL)
        |
        +---> dbt-core (single trend mart, full-refresh nightly via GitHub Actions)
                     |
                     v
                 fct_repo_trends_daily (table in S3 + Glue)
                     |
                     v
   embeddings job (offline, runs weekly):
     Athena top-N repos -> GitHub API enrichment -> sentence-transformers
     -> S3: vectors.npy + repos.parquet
                     |
                     v
   Streamlit Community Cloud (free, always-on)
     - Trends page reads from Athena (cached 1h)
     - Search page loads numpy vectors from S3, runs cosine similarity in memory
```

## Folder structure

```
abiral2project/
  PHASES.md                  # the build guide (v2, ~75 hours)
  PHASES_V1.md               # archived ambitious version (kept for context)
  NEXT.md                    # v2 ideas — what was cut from v1 and why
  Makefile                   # common commands
  .env.example               # rename to .env, fill in values
  bootstrap/                 # one-time scripts (state backend creation)
  terraform/                 # all infra as code
    modules/                 # reusable terraform modules
    envs/dev/                # env-specific tfvars
  lambda/
    ingest_gh_archive/       # hourly ingest function
  dbt/                       # dbt-core project
    models/staging/
    models/intermediate/
    models/marts/
  embeddings/                # offline numpy vector index builder
  streamlit/                 # dashboard + semantic search UI (deploys to Streamlit Cloud)
    pages/
  analysis/queries/          # raw Athena SQL for ad-hoc analysis
  .github/workflows/         # CI/CD
```

## Pre-flight decisions (locked)

- **Vector search:** numpy cosine similarity over 500-1000 precomputed embeddings stored in S3. Not pgvector. Not RDS.
- **Demo hosting:** Streamlit Community Cloud (free, always-on). No EC2.
- **Lake format:** plain Parquet partitioned by date, catalog via Glue Crawler. Not Iceberg.
- **Cost cap:** AWS billing alarm at $3, second at $10.

These are *judgment calls*, not laziness. See `NEXT.md` for what each cut would buy and when it would be worth adding.

## Cost expectations

- During AWS 12-month free tier window: ~$0-1/month
- After free tier (month 13+): ~$0-2/month (S3 storage is the only ongoing cost)
- Streamlit Community Cloud: free forever for public apps

## Quick start (after Phase 1 is complete)

```bash
make bootstrap        # one-time: create S3 + DynamoDB for terraform state
make tf-init          # initialize terraform
make tf-plan          # see what will be created
make tf-apply         # actually create infra
make tf-destroy       # tear everything down
```

## License

MIT.
