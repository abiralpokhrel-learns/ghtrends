# 10-Phase Build Plan

This is your build manual. Read each phase fully before starting it. Do not skip the "What you must NOT do" sections — that's how scope creep is contained.

## How to use this document

1. Pick a phase. Read the whole phase before writing any code.
2. Work through steps in order. Each step has an estimated time.
3. At the end of each phase, run the **Verification** checklist. Do not advance until every box is checked.
4. If a step fails, check **Common pitfalls** before asking for help.
5. Update `docs/FINDINGS.md` (you create this in Phase 10) with anything you learned that surprised you.

## Total time

| | Hours |
|---|---|
| Sum of phase estimates | ~108 |
| Realistic with debugging buffer (+30%) | ~140 |
| At 12 hrs/week | 12 weeks |
| At 8 hrs/week | 17-18 weeks |

If you hit hour 50 and feel behind: that's normal. Phases 3-7 are where complexity peaks.

## Pre-flight decisions (already locked)

- Vector DB: **Postgres + pgvector in Docker on EC2**. Not RDS.
- Demo strategy: **Pre-recorded Loom video as primary**, on-demand spin-up for serious interviews.
- Cost cap: **billing alarm at $3, second at $10**. Tear down via `make demo-down` between sessions.

## Hard rules across all phases

- Every infra change goes through Terraform. No console clicks except where explicitly noted.
- Tag every AWS resource with `Project=ghtrends` and `Env=dev`. Already enforced by `terraform/providers.tf`.
- Don't refactor between phases. Build ugly first; refactor never (or in v2).
- Don't commit secrets. `.env` is gitignored. Use AWS Secrets Manager for anything sensitive.
- Use the `Makefile` targets, not raw commands. If a target doesn't exist for what you need, add it.

---

# Phase 1 — Foundations and Terraform state backend

**Estimated time: 10 hours**

## Goal

End state: AWS account with cost guardrails, working Terraform setup with remote state in S3 + DynamoDB, and a verified `terraform apply` / `terraform destroy` cycle on a trivial resource (S3 buckets).

## Prerequisites

- A credit card (AWS requires one even for free tier)
- A fresh email address you'll use only for this AWS account
- Local machine with admin rights to install software

## Decisions you made earlier that apply here

- Postgres in Docker on EC2 means **no RDS module** in Terraform. Your `main.tf` only references `data_lake`, `lambda_ingest`, `glue_catalog`, `step_functions`, `worker` (EC2).
- On-demand demo means **no always-on infrastructure**. Every Terraform module must support clean `destroy` and recreate.

## Step-by-step

### Step 1.1 — Create dedicated AWS account (30 min)

1. Go to `aws.amazon.com` and click "Create an AWS Account".
2. Use a fresh email like `youraddress+aws-ghtrends@gmail.com`. The `+ghtrends` part is a Gmail trick that lets you receive mail at your normal inbox while AWS thinks it's a separate address.
3. Fill in the form. You'll need a credit card (AWS won't charge unless you exceed free tier, but they need one on file).
4. Choose "Basic Support — Free" plan.
5. Save the root password in your password manager. You'll rarely use root after this step.

**Why a fresh account:** keeps billing isolated. If you blow up costs on this project, it can't drain a personal account. Also, free-tier credits reset for new accounts.

### Step 1.2 — Enable MFA on root user (15 min)

1. Sign into the AWS console as root.
2. Go to **IAM** → **My security credentials** (top right corner).
3. Under "Multi-factor authentication", click **Activate MFA**.
4. Use a TOTP app like Authy or your password manager. Do not use SMS — it's less secure.
5. Save the backup codes somewhere safe (password manager).

### Step 1.3 — Create IAM admin user (15 min)

1. **IAM** → **Users** → **Create user**.
2. Name: `terraform-admin`.
3. Tick "Provide user access to the AWS Management Console" if you want console access too.
4. Permissions: attach `AdministratorAccess` directly. We'll tighten this in Phase 9.
5. After creation, go to the user → **Security credentials** tab → **Create access key** → choose "Command Line Interface (CLI)" → save the access key ID and secret somewhere.
6. Configure local AWS CLI:
   ```
   aws configure --profile ghtrends
   ```
   Paste the key, secret, region `us-east-1`, output `json`.
7. Verify:
   ```
   aws sts get-caller-identity --profile ghtrends
   ```
   Should print your account ID and user ARN.

### Step 1.4 — Set up billing alarms (30 min)

Billing metrics live only in `us-east-1`, even if you work in another region.

1. Console → top right → **Account name → Account**.
2. Scroll to "Billing preferences" → enable "Receive AWS Free Tier alerts" and "Receive Billing Alerts".
3. Switch region to **us-east-1**.
4. **CloudWatch** → **Alarms** → **Create alarm** → **Select metric** → **Billing** → **Total Estimated Charge** → currency USD.
5. Set threshold: greater than `3`.
6. Create new SNS topic, name it `billing-alerts`, enter your email. Confirm the subscription email.
7. Repeat for a second alarm at threshold `10` (safety net).
8. **AWS Budgets** → **Create budget** → "Cost budget" → Monthly budget `$5` → alerts at 50/80/100% of budget → notify your email.

**Verify billing alarm works:** Temporarily lower threshold to `0.01` and wait 24 hours. If it fires, your alarm config is correct. Then put it back to `3`.

### Step 1.5 — Install local tools (30 min)

You need: Terraform >= 1.6, AWS CLI v2, Git, Docker, Make.

**Windows:**
- Install [Chocolatey](https://chocolatey.org/install)
- `choco install terraform awscli git docker-desktop make`

**Mac:**
- Install [Homebrew](https://brew.sh/)
- `brew install tfenv awscli git docker make`
- `tfenv install 1.6.6 && tfenv use 1.6.6`

**Linux:**
- See HashiCorp's apt repo instructions for terraform.
- `sudo apt install awscli git docker.io make`

Verify:
```
terraform version    # >= 1.6
aws --version
git --version
docker --version
make --version
```

### Step 1.6 — Create Terraform state backend (1 hour)

This is the chicken-and-egg step. Your Terraform state needs to live in S3 + DynamoDB. But those resources have to exist before `terraform init` works. So you create them once via shell script.

1. From the project root, copy `.env.example` to `.env`.
2. Edit `.env` and set `AWS_PROFILE=ghtrends`, `AWS_REGION=us-east-1`, `PROJECT_NAME=ghtrends`.
3. Run:
   ```
   make bootstrap
   ```
   This calls `bootstrap/create_state_backend.sh`, which creates:
   - S3 bucket `ghtrends-tfstate-<your-account-id>` with versioning + encryption + public access block
   - DynamoDB table `tfstate-locks` for state locking
4. Note the bucket name printed at the end.
5. Open `terraform/backend.tf`, replace `<TFSTATE_BUCKET>` with the bucket name from step 4.
6. Open `.env` and set `TFSTATE_BUCKET=<bucket-name>`.

### Step 1.7 — Initialize Terraform (30 min)

1. From project root:
   ```
   make tf-init
   ```
2. You should see "Successfully configured the backend 's3'!"
3. If you see errors about credentials, re-check `aws sts get-caller-identity --profile ghtrends`.

### Step 1.8 — First apply: data lake S3 buckets (2 hours)

The `terraform/main.tf` already has the `data_lake` module enabled and uncommented. The `s3_data_lake` module creates two buckets: `ghtrends-dev-raw` and `ghtrends-dev-iceberg`.

1. Run:
   ```
   make tf-plan
   ```
   Read every line. You should see "Plan: 11 to add, 0 to change, 0 to destroy."
2. Run:
   ```
   make tf-apply
   ```
   Type `yes`.
3. Console → S3 → confirm both buckets exist with versioning enabled.

### Step 1.9 — Verify destroy/recreate cycle (1 hour)

Critical: prove your setup is reproducible.

1. Run `make tf-destroy`. Type `yes`.
2. Console → buckets are gone.
3. Run `make tf-apply`. They come back identical.

If destroy fails with "bucket not empty", that's because lifecycle versioning leaves files behind. Add `force_destroy = true` to the `aws_s3_bucket` resources for dev only. Document this in your README.

### Step 1.10 — Initial git commit and push (30 min)

1. Create a new public repo on GitHub named `ghtrends`.
2. From project root:
   ```
   git init
   git add .
   git commit -m "Phase 1: foundations and state backend"
   git branch -M main
   git remote add origin git@github.com:YOUR_USERNAME/ghtrends.git
   git push -u origin main
   ```
3. Verify on GitHub that no `.env`, `*.tfstate`, or AWS keys appear in the commit.

## Files produced this phase

- `.env` (local, gitignored) populated with your real values
- `terraform/backend.tf` updated with your real bucket name
- New AWS resources: S3 state bucket, DynamoDB lock table, two S3 data buckets, SNS topic, billing alarms

## Verification — done means

- [ ] `aws sts get-caller-identity --profile ghtrends` returns your account info
- [ ] CloudWatch billing alarms exist at $3 and $10, status OK
- [ ] AWS Budget at $5 with 50/80/100% alerts
- [ ] `make tf-apply` and `make tf-destroy` both run cleanly
- [ ] Public GitHub repo exists with this code, no secrets committed
- [ ] You can answer aloud: "Where is my Terraform state? Why DynamoDB?"

## Common pitfalls

- **MFA enforcement breaks API access.** If you require MFA on the IAM user, your local AWS CLI calls fail. For dev, keep MFA on root only.
- **Bucket name conflict.** S3 bucket names are globally unique. The bootstrap script uses your account ID to avoid this. If `ghtrends-dev-raw` is taken, change `project_name` in `tfvars`.
- **Forgot to confirm SNS subscription email.** Alarms won't send. Check your spam folder.
- **Billing alarm in wrong region.** Must be us-east-1 even if everything else lives elsewhere.
- **Committed `.env`.** Run `git rm --cached .env` and verify `.gitignore` covers it.

## What you must NOT do in this phase

- Do NOT write the Lambda yet
- Do NOT create RDS or EC2 yet
- Do NOT loosen the public access block on S3 buckets — they should never be public
- Do NOT skip the destroy/recreate verification

---

# Phase 2 — Ingestion Lambda (GH Archive to S3 raw)

**Estimated time: 12-16 hours**

## Goal

A Lambda function that, given an hour timestamp, downloads the corresponding GH Archive `.json.gz` file, filters to `WatchEvent` and `PullRequestEvent` events, flattens them, and writes Parquet to S3 partitioned by event type and date.

## Prerequisites

- Phase 1 complete
- Docker working locally (needed to build the Lambda zip with the right binary deps)

## Step-by-step

### Step 2.1 — Read the existing handler skeleton (30 min)

Open `lambda/ingest_gh_archive/handler.py`. Read every line. The structure is:

1. `lambda_handler` — entrypoint, called by Step Functions or EventBridge
2. `_resolve_target_hour` — figures out which hour to download
3. `_download_with_retry` — pulls the gzipped file from gharchive.org with backoff
4. `_iter_events` — streams JSON lines out of the gzip
5. `_flatten` — projects the nested event into flat columns
6. `_write_parquet` — uploads Parquet to S3

Do not modify until you understand the flow.

### Step 2.2 — Test the handler locally (1 hour)

1. From `lambda/ingest_gh_archive/`:
   ```
   python -m venv venv
   source venv/bin/activate    # or venv\Scripts\activate on Windows
   pip install -r requirements.txt
   ```
2. Set env vars:
   ```
   export RAW_BUCKET=ghtrends-dev-raw
   export AWS_PROFILE=ghtrends
   ```
3. Run for a known good hour (the one before now):
   ```
   python handler.py 2026-04-01T13:00:00Z
   ```
4. You should see logs: download → write Parquet for `WatchEvent` → write Parquet for `PullRequestEvent`.
5. Check S3:
   ```
   aws s3 ls s3://ghtrends-dev-raw/raw/event_type=WatchEvent/year=2026/month=04/day=01/hour=13/ --profile ghtrends
   ```
   Should show one `data.parquet` file.

### Step 2.3 — Build the deployment zip (1 hour)

`pyarrow` has compiled C extensions. The Lambda runtime uses Amazon Linux 2. If you build the zip on your laptop (Mac or Windows), `pyarrow` won't load on Lambda. Use Docker to build inside the official Lambda runtime image.

1. Run:
   ```
   make lambda-package
   ```
   This calls `lambda/ingest_gh_archive/build.sh` which:
   - Spins up a `public.ecr.aws/lambda/python:3.11` container
   - Installs requirements into a `build/` dir
   - Copies `handler.py` in
   - Zips it as `ingest_gh_archive.zip`
2. Check size: should be 30-60 MB. If larger, you forgot to use the Lambda runtime image.

### Step 2.4 — Create the Terraform module (4 hours)

Create `terraform/modules/lambda_ingest/main.tf` with:

- `aws_iam_role` for the Lambda with assume-role policy for `lambda.amazonaws.com`
- `aws_iam_role_policy` granting `s3:PutObject` on the raw bucket and `logs:*` for CloudWatch
- `aws_lambda_function` with:
  - `runtime = "python3.11"`
  - `memory_size = 512`
  - `timeout = 300`
  - `filename = "../lambda/ingest_gh_archive/ingest_gh_archive.zip"`
  - `source_code_hash = filebase64sha256(...)`
  - env vars: `RAW_BUCKET = var.raw_bucket_name`
- `aws_cloudwatch_log_group` with retention 14 days

Hint on structure: copy the pattern from `terraform/modules/s3_data_lake/main.tf`. Inputs as `variable` blocks at the top, outputs at the bottom.

### Step 2.5 — Wire the module into main.tf (15 min)

In `terraform/main.tf`, uncomment the `module "ingest_lambda"` block. Run `make tf-plan` then `make tf-apply`.

### Step 2.6 — Invoke from console to verify (30 min)

1. Lambda console → your function → **Test** tab.
2. Event JSON: `{"timestamp": "2026-04-01T13:00:00Z"}`.
3. Click Test. Should succeed in 30-60 seconds.
4. Check S3 bucket → new Parquet file appears.
5. Check CloudWatch Logs for the `counts` log line.

### Step 2.7 — Add idempotency safeguard (2 hours)

Right now if the Lambda is invoked twice for the same hour, it overwrites. That's fine for now but document it. Add a check at the top of `lambda_handler`:

```python
key = f"raw/event_type=WatchEvent/year={dt.year}/.../data.parquet"
try:
    s3.head_object(Bucket=RAW_BUCKET, Key=key)
    log.info("Already ingested hour=%s, skipping", dt.isoformat())
    return {"statusCode": 200, "skipped": True}
except s3.exceptions.ClientError:
    pass  # not exists, proceed
```

Test by running twice for the same hour. Second run should skip.

### Step 2.8 — Backfill last 7 days manually (3 hours)

For Phase 3 you'll need data to query. Run a quick backfill script:

```
for d in 2026-04-25 2026-04-26 2026-04-27 ...
do
    for h in {0..23}
    do
        aws lambda invoke --function-name ghtrends-dev-ingest \
            --payload "{\"timestamp\": \"${d}T${h}:00:00Z\"}" \
            --profile ghtrends \
            response_${d}_${h}.json
    done
done
```

This will cost you nothing (still in free tier) but takes ~30 minutes for a week.

## Files produced this phase

- `lambda/ingest_gh_archive/ingest_gh_archive.zip` (built artifact, gitignored)
- `terraform/modules/lambda_ingest/main.tf` (new)
- `terraform/main.tf` updated with module reference

## Verification — done means

- [ ] Lambda runs for one hour and writes Parquet to S3
- [ ] Re-running for the same hour skips with idempotency check
- [ ] At least 7 days × 24 hours = 168 Parquet files exist in S3
- [ ] CloudWatch log group has retention 14 days
- [ ] You can answer: "How many events did I ingest in the last 7 days?" (Look at file sizes)

## Common pitfalls

- **PyArrow ImportError on Lambda.** You built the zip outside Docker. Fix: use `make lambda-package`.
- **Timeout at 5 min.** A few hours have huge files. Bump timeout to 10 min if you see timeout errors.
- **GH Archive 404.** That hour hasn't published yet. Default to "now - 2 hours" not "now - 1 hour".
- **Pricey log volume.** Add `retention_in_days = 14` on the log group, otherwise logs accumulate forever.

## What you must NOT do in this phase

- Do NOT add Step Functions or EventBridge yet (Phase 6)
- Do NOT add more event types beyond Watch and PR (storage cost discipline)
- Do NOT skip the local test before deploying to AWS

---

# Phase 3 — Iceberg lake and Glue Catalog

**Estimated time: 12-14 hours**

## Goal

Apache Iceberg tables `watch_events` and `pull_request_events` registered in the AWS Glue Catalog, queryable from Athena. The Parquet files written by Lambda in Phase 2 become rows in those tables.

## Prerequisites

- Phase 2 complete with at least 7 days of Parquet files in S3
- Athena workgroup using engine version 3 (Iceberg requires v3)

## Step-by-step

### Step 3.1 — Create Glue database via Terraform (1 hour)

Create `terraform/modules/glue_catalog/main.tf`:

```hcl
variable "project_name" { type = string }
variable "env" { type = string }
variable "lake_bucket" { type = string }

resource "aws_glue_catalog_database" "lake" {
  name = "ghtrends_lake"
  description = "Iceberg lakehouse for GH Archive trends"
}

output "database_name" {
  value = aws_glue_catalog_database.lake.name
}
```

Wire into `terraform/main.tf`. Apply.

### Step 3.2 — Configure Athena workgroup (1 hour)

Athena queries scan S3 and the cost is per-byte. Configure your workgroup to fail any query that scans more than 1 GB — protects you from runaway costs.

In the Athena console:
1. Workgroups → primary → Edit
2. Query result location: `s3://ghtrends-dev-iceberg/athena_results/`
3. Engine version: **Athena engine version 3**
4. Query result encryption: SSE_S3
5. Per query data scanned limit: 1 GB
6. Workgroup data scanned limit: 10 GB per day

Athena engine v3 is required for Iceberg.

### Step 3.3 — Create Iceberg tables (3 hours)

In Athena console, run:

```sql
CREATE TABLE ghtrends_lake.watch_events (
    id string,
    type string,
    actor_id bigint,
    actor_login string,
    repo_id bigint,
    repo_name string,
    created_at timestamp,
    pr_action string,
    pr_merged boolean,
    pr_state string,
    pr_base_ref string,
    pr_user_login string
)
PARTITIONED BY (year, month, day)
LOCATION 's3://ghtrends-dev-iceberg/iceberg/watch_events/'
TBLPROPERTIES (
    'table_type' = 'ICEBERG',
    'format' = 'parquet',
    'write_compression' = 'snappy'
);
```

Repeat for `pull_request_events` (same schema, different name and location).

### Step 3.4 — Migrate Parquet from raw to Iceberg (4 hours)

The Lambda wrote raw Parquet at `s3://...-raw/raw/event_type=X/year=Y/...`. The Iceberg tables need data inserted via Athena `INSERT INTO ... SELECT FROM` so Iceberg can manage its own metadata.

Option A: register raw as an external table, then `INSERT INTO iceberg SELECT * FROM raw`.

```sql
CREATE EXTERNAL TABLE ghtrends_lake.watch_events_raw (
    id string,
    type string,
    actor_id bigint,
    ...
)
PARTITIONED BY (year int, month int, day int, hour int)
STORED AS PARQUET
LOCATION 's3://ghtrends-dev-raw/raw/event_type=WatchEvent/'
TBLPROPERTIES ('parquet.compression'='SNAPPY');

MSCK REPAIR TABLE ghtrends_lake.watch_events_raw;

INSERT INTO ghtrends_lake.watch_events
SELECT id, type, actor_id, actor_login, repo_id, repo_name,
       cast(created_at as timestamp) as created_at,
       pr_action, pr_merged, pr_state, pr_base_ref, pr_user_login,
       year, month, day
FROM ghtrends_lake.watch_events_raw;
```

Repeat for `pull_request_events`.

### Step 3.5 — Decision: how does fresh data get into Iceberg? (3 hours)

The Lambda writes raw Parquet, not Iceberg. You need a periodic step that pulls new raw partitions into Iceberg. Two options:

**Option A: Athena INSERT in Step Functions (Phase 6).** Lambda writes raw → Step Functions runs Athena `INSERT INTO ... SELECT WHERE day = today` → done. Simple. ~5 cents/day in Athena scans.

**Option B: Modify Lambda to write directly to Iceberg via PyIceberg.** Couples ingest to Iceberg version. More fragile.

**Pick Option A.** Defer the actual implementation to Phase 6 — for now, just run the migration query manually whenever you need fresh data in Iceberg.

### Step 3.6 — Verify queries work (1 hour)

In Athena, run:

```sql
SELECT count(*) FROM ghtrends_lake.watch_events;

SELECT repo_name, count(*) as stars
FROM ghtrends_lake.watch_events
WHERE year = 2026 AND month = 4
GROUP BY repo_name
ORDER BY stars DESC
LIMIT 10;
```

Both should run in <10 seconds, scanning <100 MB.

## Files produced this phase

- `terraform/modules/glue_catalog/main.tf` (new)
- Iceberg DDL captured in `analysis/queries/00_create_iceberg_tables.sql` (you create this file)
- Manual notes in your README about how to migrate raw → Iceberg

## Verification — done means

- [ ] `SELECT count(*) FROM ghtrends_lake.watch_events;` returns a number > 0
- [ ] Athena workgroup has 1 GB per-query and 10 GB per-day limits
- [ ] Time-travel query works: `SELECT * FROM ghtrends_lake.watch_events FOR VERSION AS OF <snapshot_id> LIMIT 5`
- [ ] You can answer: "What does Iceberg give me that plain Parquet doesn't?"

## Common pitfalls

- **Engine version 2 silently won't accept Iceberg DDL.** Switch to v3 in workgroup settings.
- **Glue catalog permissions.** Your IAM user needs `glue:*` on the database. AdministratorAccess covers it for dev.
- **MSCK REPAIR is slow on the raw external table** if you have many partitions. Be patient.

## What you must NOT do in this phase

- Do NOT skip the workgroup data scanned limits — without them, one bad query can cost $20
- Do NOT enable Iceberg in production-recommended ways yet (snapshot expiration, file compaction) — Phase 9
- Do NOT add more tables — only watch_events and pull_request_events for now

---

# Phase 4 — Athena queries and smoke tests

**Estimated time: 6 hours**

## Goal

A `analysis/queries/` folder with 8-10 SQL files that produce real findings about GitHub trends. These are the queries you'll show recruiters and the queries that feed your dbt models in Phase 5.

## Prerequisites

- Phase 3 complete; Iceberg tables have at least 7 days of data

## Step-by-step

### Step 4.1 — Read the three example queries (15 min)

Open `analysis/queries/01_top_starred_repos.sql`, `02_star_velocity.sql`, `03_pr_merge_rate.sql`. Run each against Athena. Verify results look sane.

### Step 4.2 — Build out the rest of the suite (4 hours)

Create these additional query files:

- `04_top_organizations.sql` — top orgs by total event volume
- `05_active_users.sql` — top contributors by PR count
- `06_language_trends.sql` — requires GitHub API enrichment (defer until Phase 7)
- `07_hourly_star_distribution.sql` — what time of day are stars happening?
- `08_emerging_repos.sql` — repos that crossed 100 stars/day for the first time

For each query, document at the top: estimated runtime, bytes scanned, and what finding it produces.

### Step 4.3 — Capture findings (1 hour)

Run each query. Screenshot the top 10 results. Save in `analysis/findings/` as PNGs. You'll embed these in the README in Phase 10.

### Step 4.4 — Set query budget (30 min)

In Athena console, check "Query history" → "Data scanned" column. Compute total over the past 24 hours. If > 1 GB, your queries aren't using partition pruning. Fix by adding `WHERE year = X AND month = Y AND day = Z` to all queries.

## Files produced this phase

- `analysis/queries/04_*.sql` through `08_*.sql`
- `analysis/findings/*.png` screenshots
- Notes in each query file about runtime and scan size

## Verification — done means

- [ ] 8 query files exist, all run successfully on the current Iceberg data
- [ ] Each query scans < 500 MB
- [ ] You have screenshots saved
- [ ] You can describe one finding from each query in plain English

## Common pitfalls

- **Forgot partition pruning.** If a query scans the whole table, add date predicates.
- **NULL repo_name confuses GROUP BY.** Filter `WHERE repo_name IS NOT NULL` if results look weird.

## What you must NOT do in this phase

- Do NOT enrich with GitHub API yet (that's Phase 7's job)
- Do NOT build dbt models yet — these queries are inputs to Phase 5

---

# Phase 5 — dbt-core models and trend marts

**Estimated time: 12-14 hours**

## Goal

A working dbt project that reads from the Iceberg sources, builds staging views, intermediate aggregates, and a final mart `fct_repo_trends_daily` that the dashboard will query.

## Prerequisites

- Phase 4 complete
- Athena workgroup configured for Iceberg
- Python 3.10+ installed locally

## Step-by-step

### Step 5.1 — Install dbt locally (30 min)

```
python -m venv .venv
source .venv/bin/activate
pip install dbt-athena-community==1.7.2
```

Configure `~/.dbt/profiles.yml` from the example in `dbt/profiles.yml.example`. Make sure `aws_profile_name: ghtrends` matches your AWS CLI profile.

### Step 5.2 — Verify connection (15 min)

```
cd dbt
dbt debug
```

Should print "All checks passed!".

### Step 5.3 — Read the existing models (30 min)

Open and understand:
- `dbt/models/staging/_sources.yml` — declares the Iceberg tables as dbt sources
- `dbt/models/staging/stg_watch_events.sql` — clean column names
- `dbt/models/staging/stg_pull_request_events.sql` — clean column names
- `dbt/models/intermediate/int_repo_daily_activity.sql` — combines stars and PRs
- `dbt/models/marts/fct_repo_trends_daily.sql` — final mart with rolling windows

### Step 5.4 — Run the build (1 hour)

```
dbt deps
dbt build
```

Watch the output. Each model runs as a query in Athena. The mart materializes as an Iceberg table.

If a query fails, read the SQL printed in the dbt log and run it manually in Athena to debug.

### Step 5.5 — Add tests (3 hours)

The `_schema.yml` already has tests for `unique_combination_of_columns`, `not_null`, and `accepted_range`. Add three more:

- A custom test that `pr_merge_rate` is between 0 and 1 (already there as accepted_range)
- A custom singular test in `dbt/tests/` named `assert_no_future_dates.sql`:
  ```sql
  select * from {{ ref('fct_repo_trends_daily') }}
  where event_date > current_date
  ```
- Source freshness — declare in `_sources.yml`:
  ```yaml
  freshness:
    warn_after: { count: 3, period: hour }
    error_after: { count: 6, period: hour }
  loaded_at_field: created_at
  ```

Run `dbt test` and `dbt source freshness`.

### Step 5.6 — Add 2 more marts (4 hours)

Create:

- `dbt/models/marts/dim_repos.sql` — one row per repo with cumulative stats
- `dbt/models/marts/fct_org_activity_daily.sql` — one row per org per day

Add `_schema.yml` entries for both.

### Step 5.7 — Generate dbt docs site (2 hours)

```
dbt docs generate
dbt docs serve   # opens at localhost:8080
```

Push the `target/` static site to a `gh-pages` branch on your GitHub repo. Docs become a public URL — looks great on resume.

## Files produced this phase

- `dbt/models/marts/dim_repos.sql`
- `dbt/models/marts/fct_org_activity_daily.sql`
- `dbt/tests/assert_no_future_dates.sql`
- Updated `_schema.yml` files with tests
- Public dbt docs site on GitHub Pages

## Verification — done means

- [ ] `dbt build` runs end-to-end with all tests passing
- [ ] Mart row counts match raw aggregates within 0.1%
- [ ] Public dbt docs site is live
- [ ] You can answer: "What's the difference between staging, intermediate, and mart layers?"

## Common pitfalls

- **dbt-athena Iceberg incremental models are flaky.** If incremental fails, fall back to `materialized='table'` with full refresh. Acceptable for this data volume.
- **Athena workgroup mismatch.** Make sure `dbt_project.yml` and `profiles.yml` both point to the same workgroup.
- **Permissions.** Your IAM user needs `glue:*` on `ghtrends_lake` and `s3:*` on the iceberg bucket. AdministratorAccess covers it for dev.

## What you must NOT do in this phase

- Do NOT add macros or custom Jinja for cleverness. Keep models readable.
- Do NOT enable incremental until you've shipped the full-refresh version

---

# Phase 6 — Orchestration (Step Functions + EventBridge)

**Estimated time: 8 hours**

## Goal

EventBridge fires hourly. Step Functions runs the ingest Lambda for the previous hour, then runs an Athena INSERT to load Iceberg, then once per day kicks off a dbt build via ECS Fargate.

## Prerequisites

- Phases 2, 3, 5 complete

## Step-by-step

### Step 6.1 — Design the state machine (1 hour)

States:

1. `IngestRawHour` — call Lambda from Phase 2 with the previous hour's timestamp
2. `LoadToIceberg` — Athena INSERT INTO from raw → iceberg for the day
3. `IsEndOfDay?` — choice state: if hour == 23, branch to dbt build
4. `RunDbtBuild` — ECS Fargate task running `dbt build`
5. `Success` / `Fail` end states

### Step 6.2 — Build the dbt Fargate container (3 hours)

Create `dbt/Dockerfile`:

```dockerfile
FROM python:3.11-slim
WORKDIR /app
COPY . /app
RUN pip install dbt-athena-community==1.7.2
ENV DBT_PROFILES_DIR=/app
CMD ["dbt", "build"]
```

Build, push to ECR (Terraform creates the ECR repo).

### Step 6.3 — Terraform module for orchestration (3 hours)

Create `terraform/modules/step_functions/main.tf`:

- `aws_sfn_state_machine` with the JSON definition
- `aws_iam_role` for Step Functions to invoke Lambda + Athena + ECS
- `aws_cloudwatch_event_rule` with cron expression `cron(5 * * * ? *)` (5 minutes after each hour)
- `aws_cloudwatch_event_target` pointing to the state machine

### Step 6.4 — Test one full cycle (1 hour)

Trigger the state machine manually from the console with a test input. Watch each state turn green.

## Files produced this phase

- `terraform/modules/step_functions/main.tf`
- `terraform/modules/step_functions/sfn_definition.json`
- `dbt/Dockerfile`

## Verification — done means

- [ ] State machine succeeds for one hour end-to-end
- [ ] EventBridge cron is enabled and firing
- [ ] Failure on any state sends an SNS email
- [ ] Watch one full 24-hour cycle. Count failures. Should be 0 or 1.

## Common pitfalls

- **dbt in Lambda is painful** (15-min limit, 250 MB unzipped). Use Fargate.
- **Step Functions state machine is one massive JSON.** Use ASL (Amazon States Language) reference docs heavily.

## What you must NOT do in this phase

- Do NOT auto-retry a failed dbt run more than 2 times — failures usually mean a real bug, retries waste money

---

# Phase 7 — Embeddings + Postgres in Docker + pgvector

**Estimated time: 14-16 hours**

## Goal

Top 10K trending repos have embeddings stored in pgvector, searchable via cosine similarity in <100ms.

## Prerequisites

- Phase 5 complete (need `fct_repo_trends_daily` mart)
- GitHub Personal Access Token (no scopes needed, just a public read token)

## Step-by-step

### Step 7.1 — Provision EC2 worker via Terraform (3 hours)

Create `terraform/modules/ec2_workhorse/main.tf`:

- VPC with public subnet (or default VPC for simplicity)
- Security group: allow 22 (SSH from your IP), 80 (HTTPS via nginx), 443 (HTTPS)
- EC2 t3.micro with Amazon Linux 2023, Docker pre-installed via user-data
- Elastic IP attached
- IAM instance profile with `s3:Get*` and `athena:*` and `glue:*`

User-data script installs Docker, docker-compose, git, Python, then clones your repo.

### Step 7.2 — Bring up Postgres on EC2 (2 hours)

SSH into the instance.

```
git clone https://github.com/YOU/ghtrends.git
cd ghtrends/embeddings
echo "PG_PASSWORD=$(openssl rand -base64 24)" > .env
docker-compose up -d
```

Verify:
```
docker exec -it ghtrends-pg psql -U ghtrends -c "select * from pg_extension where extname='vector';"
```

Should show one row.

### Step 7.3 — Run the embedding pipeline (4 hours)

```
cd embeddings
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
export ATHENA_OUTPUT_S3=s3://ghtrends-dev-iceberg/athena_results/
export GITHUB_PAT=...
export PG_DSN="postgresql://ghtrends:PASSWORD@127.0.0.1:5432/ghtrends"
python embed_repos.py --top 10000
```

Expect: 60-120 minutes. The bottleneck is GitHub API rate limit (5000 req/hour with PAT). The script is resumable.

### Step 7.4 — Build the search sidecar (3 hours)

The sentence-transformers model is too big to load inside Streamlit on a 1 GB box. Build a tiny Flask app that loads the model once and serves embeddings on `localhost:8000/embed`.

Create `embeddings/sidecar.py`:

```python
from flask import Flask, request, jsonify
from sentence_transformers import SentenceTransformer

app = Flask(__name__)
model = SentenceTransformer("sentence-transformers/all-MiniLM-L6-v2")

@app.post("/embed")
def embed():
    text = request.json["text"]
    vec = model.encode(text).tolist()
    return jsonify({"embedding": vec})

if __name__ == "__main__":
    app.run(host="127.0.0.1", port=8000)
```

Run as a systemd service so it stays up.

### Step 7.5 — Verify search works (1 hour)

```
curl -X POST http://localhost:8000/embed -d '{"text":"data engineering pipelines"}' -H "Content-Type: application/json"
```

Should return 384-dim vector. Then query Postgres with the vector.

## Files produced this phase

- `terraform/modules/ec2_workhorse/main.tf`
- `embeddings/sidecar.py`
- `embeddings/sidecar.service` (systemd unit file)

## Verification — done means

- [ ] EC2 instance accessible via SSH from your IP
- [ ] Postgres running with pgvector extension
- [ ] 10K repos in `repos` table with non-null embeddings
- [ ] Sidecar responds in <500ms per request
- [ ] Cosine similarity query returns sensible neighbors for a test query

## Common pitfalls

- **OOM on t3.micro during embedding.** Run the embed_repos.py with smaller batches (16 instead of 64).
- **GitHub API rate limit.** Even with PAT, 5000/hour is the cap. 10K repos = 2 hours minimum. Plan accordingly.
- **Postgres connection from outside EC2.** Don't open port 5432. SSH tunnel for debugging only.

## What you must NOT do in this phase

- Do NOT expose Postgres on the public internet
- Do NOT skip the systemd service — without it, the sidecar dies on reboot
- Do NOT load the embedding model inside Streamlit

---

# Phase 8 — Streamlit dashboard and semantic search UI

**Estimated time: 12 hours**

## Goal

A Streamlit app on the EC2 worker with three pages: Trends, Search, About. Accessible via HTTPS at a domain you own.

## Prerequisites

- Phase 7 complete

## Step-by-step

### Step 8.1 — Test Streamlit locally (2 hours)

On your laptop:
```
cd streamlit
pip install -r requirements.txt
export ATHENA_OUTPUT_S3=s3://ghtrends-dev-iceberg/athena_results/
export PG_DSN="postgresql://..."     # SSH tunnel to EC2 Postgres
export EMBED_SIDE_CAR_URL=http://127.0.0.1:8000/embed
streamlit run app.py
```

Open localhost:8501. All three pages should work.

### Step 8.2 — Deploy to EC2 (3 hours)

SSH into EC2.
```
cd ~/ghtrends/streamlit
pip install -r requirements.txt
```

Create systemd unit `/etc/systemd/system/streamlit.service`:
```
[Unit]
Description=Streamlit dashboard
After=network.target

[Service]
User=ec2-user
WorkingDirectory=/home/ec2-user/ghtrends/streamlit
EnvironmentFile=/home/ec2-user/.env
ExecStart=/home/ec2-user/.venv/bin/streamlit run app.py --server.port=8501 --server.address=127.0.0.1
Restart=always

[Install]
WantedBy=multi-user.target
```

`sudo systemctl enable --now streamlit`.

### Step 8.3 — Set up nginx + Let's Encrypt (3 hours)

Install nginx and certbot. Create `/etc/nginx/sites-enabled/ghtrends`:
```
server {
    listen 80;
    server_name your-domain.com;
    location / {
        proxy_pass http://127.0.0.1:8501;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 86400;
    }
}
```

Run `sudo certbot --nginx -d your-domain.com`. It auto-redirects HTTP to HTTPS.

### Step 8.4 — Buy or set up a domain (1 hour)

Cheapest option: Cloudflare Registrar (~$10/year) or duckdns.org (free subdomain).

Point the A record at your Elastic IP.

### Step 8.5 — Smoke test from incognito (30 min)

Open the URL on your phone. Both pages load in <3 seconds. Search returns relevant results.

### Step 8.6 — Add About page polish (2 hours)

Update `streamlit/pages/3_About.py`:
- Replace `YOUR_USERNAME` with your real GitHub
- Add architecture diagram (Excalidraw or Mermaid)
- Add your contact info

## Files produced this phase

- `streamlit.service` systemd unit
- nginx config
- TLS cert from Let's Encrypt
- Updated About page

## Verification — done means

- [ ] HTTPS URL works from phone, laptop, incognito
- [ ] Trends page loads in <3 seconds
- [ ] Search page returns results in <500ms after first query (subsequent are cached)
- [ ] Streamlit auto-restarts after `systemctl restart streamlit`

## Common pitfalls

- **Streamlit OOMs on t3.micro under load.** Cache aggressively with `@st.cache_data`. Pin Streamlit memory: `streamlit run --server.maxUploadSize=10`.
- **Mixed content errors.** If anything in your page loads via `http://`, browsers block it. All assets via HTTPS.
- **Athena cost from refreshing dashboard repeatedly.** Cache Athena queries for 1 hour minimum.

## What you must NOT do in this phase

- Do NOT run Streamlit on port 8501 publicly. Always behind nginx + TLS.
- Do NOT skip the cache decorators

---

# Phase 9 — CI/CD, monitoring, and cost guardrails

**Estimated time: 10 hours**

## Goal

PRs trigger automated `terraform plan`, `dbt test`, and Lambda packaging. Merges to main auto-deploy. CloudWatch alarms email you on Lambda errors, data freshness drift, and cost anomalies.

## Prerequisites

- Phase 8 complete
- GitHub Actions workflow stub already exists at `.github/workflows/terraform-plan.yml`

## Step-by-step

### Step 9.1 — Set up OIDC between GitHub and AWS (3 hours)

Long-lived AWS keys in GitHub secrets are an attack vector. Use OIDC federation instead.

Create `terraform/modules/github_oidc/main.tf`:

```hcl
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_role" "github_actions" {
  name = "github-actions-terraform"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Federated = data.aws_iam_openid_connect_provider.github.arn }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:YOU/ghtrends:*"
        }
      }
    }]
  })
}
```

Attach `AdministratorAccess` (tighten in Phase 9.5).

### Step 9.2 — Add GitHub Actions workflows (2 hours)

`.github/workflows/terraform-plan.yml` already exists. Add:

- `terraform-apply.yml` — runs on merge to main, applies with manual approval
- `dbt-test.yml` — runs on PR if `dbt/**` changed
- `lambda-deploy.yml` — runs on merge if `lambda/**` changed; rebuilds zip and updates Lambda

### Step 9.3 — Add CloudWatch alarms (2 hours)

In `terraform/modules/monitoring/main.tf`:

- Lambda errors > 0 in 1 hour → SNS email
- No new objects in raw bucket for 2 hours → SNS email
- Athena query cost > $0.10 in a day → SNS email
- Step Functions execution failures > 0 → SNS email

### Step 9.4 — Add cost guardrail Lambda (2 hours)

A Lambda triggered nightly that calls Cost Explorer API. If MTD > $4, sends an SNS email "STOP NOW: spend = $X.XX". Cron: `cron(0 8 * * ? *)`.

### Step 9.5 — Tighten IAM (1 hour)

Replace `AdministratorAccess` on `terraform-admin` and `github-actions-terraform` with custom policies that grant only what's needed: S3, Glue, Athena, Lambda, IAM (limited), Step Functions, EventBridge, CloudWatch, EC2, Secrets Manager, ECR, ECS.

This is tedious but a real resume bullet.

## Files produced this phase

- `.github/workflows/terraform-apply.yml`
- `.github/workflows/dbt-test.yml`
- `.github/workflows/lambda-deploy.yml`
- `terraform/modules/github_oidc/main.tf`
- `terraform/modules/monitoring/main.tf`
- `lambda/cost_guardrail/handler.py` and module

## Verification — done means

- [ ] Open a test PR. Plan posts as comment. Tests run.
- [ ] Merge it. Apply runs and succeeds.
- [ ] Force a Lambda failure. Email arrives within 5 min.
- [ ] No long-lived AWS keys in GitHub secrets

## Common pitfalls

- **OIDC trust policy is fiddly.** The `sub` claim format is exactly `repo:OWNER/REPO:ref:refs/heads/BRANCH` or `repo:OWNER/REPO:pull_request`. Test with a dummy role first.
- **CloudWatch alarm in wrong region.** Each alarm is regional. Be consistent.

## What you must NOT do in this phase

- Do NOT commit AWS keys for "convenience while debugging"
- Do NOT skip the cost guardrail Lambda. It's your last line of defense.

---

# Phase 10 — Documentation, demo video, LinkedIn

**Estimated time: 8 hours**

## Goal

A recruiter lands on your repo and within 30 seconds: understands what you built, sees a working demo, knows how to contact you.

## Prerequisites

- All previous phases complete

## Step-by-step

### Step 10.1 — Polish the README (2 hours)

Replace the existing README.md with the final version. Include:

1. One-paragraph pitch at the top
2. Embedded Loom video (next step)
3. Architecture diagram (Excalidraw or Mermaid)
4. Live demo URL or "message me for live spin-up"
5. Screenshot of dashboard
6. Tech stack table
7. One-command local setup
8. Cost breakdown
9. Findings (3-5 with screenshots)
10. License

### Step 10.2 — Record the demo video (4 hours)

Script (~2 minutes):

1. (10s) "I built a serverless data platform on AWS that ingests public GitHub Archive events..."
2. (20s) Quick architecture diagram walkthrough
3. (30s) Live: open the dashboard, scroll the Trends page, point out the top trending repo
4. (30s) Live: type a semantic search query, show results
5. (20s) "All built with Terraform, dbt-core, sentence-transformers, all running for under $10/month..."
6. (10s) "Source code linked below. Reach out on LinkedIn."

Record with Loom or OBS. Do 5-10 takes. Edit out dead air. Add captions.

Embed at top of README:
```markdown
[![Demo](thumbnail.png)](https://www.loom.com/share/YOUR_LOOM_URL)
```

### Step 10.3 — Write findings doc (1 hour)

Create `docs/FINDINGS.md`. For each finding:
- One-sentence headline
- Screenshot
- The SQL query that produced it
- One-paragraph interpretation

5 findings is enough. They become LinkedIn post material.

### Step 10.4 — Write 3-5 LinkedIn post drafts (1 hour)

Each post:
- Hook: an interesting finding
- 3-4 sentences explaining
- Link to the project README
- Tag relevant people/companies

Schedule one per week for a month.

### Step 10.5 — Update profile (30 min)

LinkedIn:
- Featured section: pin the project URL
- Headline: mention "data engineer" if you want DE roles
- Experience: add the project as "personal portfolio project" with the bullets from your resume

GitHub:
- Pin the `ghtrends` repo on your profile
- Add a profile README that mentions it

## Files produced this phase

- Final `README.md`
- `docs/FINDINGS.md`
- `docs/ARCHITECTURE.md` with detailed diagrams
- `docs/posts/` with LinkedIn drafts
- Loom video URL

## Verification — done means

- [ ] Send the repo URL to one person who has not seen the project. Ask them to describe what it does in one sentence. If they get it right, you're done. If not, fix the README.
- [ ] Demo video loads and plays without buffering
- [ ] All links in README work
- [ ] LinkedIn featured section has the project pinned

## Common pitfalls

- **README too long.** Aim for the elevator pitch in the first 10 lines. Details below.
- **Demo video too long.** Anything over 3 minutes loses 80% of viewers. 90 seconds is ideal.
- **Findings sound aspirational.** Every finding must come from a real query you can re-run. Save the query alongside the finding.

## What you must NOT do in this phase

- Do NOT claim numbers you haven't measured. If you say "50M events", it must be the result of a `count(*)` you can show.
- Do NOT skip the friend-review step in verification

---

# Final notes

## When you finish Phase 10

- Tag the repo: `git tag v1.0.0 && git push --tags`
- Run `make demo-down` to tear down the stack
- Add a calendar reminder: spin up for an hour every 2 weeks to make sure nothing rotted

## What v2 looks like (future-you)

Don't start any of these now. Capture them in `NEXT.md`:

- Real-time streaming via Kinesis (replace EventBridge)
- LLM-powered RAG over repo READMEs
- More event types (PushEvent, ForkEvent)
- Multi-account deployment with prod environment

## When to ask for help

- Stuck on a step for more than 2 hours: pause, write down what you tried, ask in a forum or here
- Cost alarm fires: stop everything, run `make demo-down`, investigate before continuing
- Something works on your machine but fails in CI: it's almost always an env var or path difference

Good luck.
