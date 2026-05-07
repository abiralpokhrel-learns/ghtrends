# 6-Phase Build Plan (v2)

This is the real plan. The earlier 10-phase version is archived as `PHASES_V1.md` for context. Cuts and reasoning are documented in `NEXT.md`.

This version is written assuming you have never used AWS before. Steps are explicit. Read each phase fully before starting.

---

## How to use this document

- Each phase is self-contained. Finish one before starting the next.
- Steps are numbered. Do them in order.
- After each step, there's a "What success looks like" check. Don't move on until you see it.
- After each phase, there's a Verification checklist. Don't move to the next phase until every box is checked.
- If something fails, check **Troubleshooting** at the end of each phase before searching the internet.

## Total time

| | Hours |
|---|---|
| Sum of phase estimates | ~70 |
| Realistic with debugging buffer for first-time AWS user | ~100 |
| At 8 hrs/week | 12-13 weeks |
| At 12 hrs/week | 8-9 weeks |

## Pre-flight decisions (locked)

- **No Iceberg.** Plain Parquet partitioned by date. Glue Crawler builds the catalog.
- **No EC2, no RDS, no Docker Postgres.** Embeddings are precomputed offline, stored as numpy + parquet in S3.
- **Streamlit Community Cloud** for the public demo. Free, always-on.
- **Cost cap:** AWS billing alarm at $3, second at $10.

## Hard rules across all phases

- Every infra change goes through Terraform.
- Tag every AWS resource with `Project=ghtrends` (already enforced in `terraform/providers.tf`).
- Don't refactor between phases. Build ugly first.
- Don't commit secrets. `.env` is gitignored.
- Use `Makefile` targets, not raw commands.

---

# First-time AWS user — read this before Phase 1

If you've used AWS before, skip this section.

## What is AWS

Amazon Web Services. A collection of cloud services. We'll use 6:

| Service | What it does in our project |
|---|---|
| S3 | Stores files (Parquet, numpy, dbt output) |
| Lambda | Runs our ingest code on a schedule, no server |
| Glue Catalog | Knows where the data is and what columns it has |
| Athena | Runs SQL directly against files in S3 |
| CloudWatch | Logs from Lambda, alarms for spending |
| EventBridge | Scheduler — "run this Lambda every hour" |

## Regions

AWS runs in dozens of geographic regions (us-east-1, eu-west-1, ap-south-1, etc.). Each region is independent — a bucket in `us-east-1` is invisible from `us-west-2`.

**We use `us-east-1` (Northern Virginia) for everything.** It's the cheapest, biggest, and the only region where billing alarms work.

**Where to check the region:** top-right corner of the AWS Console. Click the dropdown to switch.

If something you "just created" seems missing, your region is probably wrong. Switch to us-east-1.

## Free tier

AWS gives 12 months of free use of small amounts of most services. After 12 months, you start paying for what you use. We're designed to stay under the free tier, so during months 1-12: ~$0-1/month total.

Month 13+: ~$2/month if everything stays running.

## The Console

`console.aws.amazon.com` is the AWS website. Sign in with your IAM admin user (which we'll create in Phase 1). When I say "go to S3" or "open IAM", I mean type that name into the search bar at the top of the console.

## What ARN means

Amazon Resource Name. A unique ID for any AWS thing. Looks like `arn:aws:s3:::your-bucket-name`. You'll copy/paste these often.

## What IAM means

Identity and Access Management. AWS's permissions system. Each user, role, or service has permissions defined in IAM.

We'll create one IAM user (`terraform-admin`) with permission to do everything we need.

## What an AWS CLI profile is

The AWS CLI on your laptop needs to know which AWS account to use. A "profile" is a named set of credentials. We'll create a profile called `ghtrends`. From then on, any AWS command takes `--profile ghtrends`.

## Things that probably will trip you up

- **Region mismatch.** Always us-east-1.
- **AWS asks for a credit card.** They charge $1 to verify, refund within 1-3 days. With our $3 alarm, you can't accidentally rack up real costs.
- **Some operations take 5-10 minutes.** Lambda deploys, IAM propagation. Be patient.
- **Same concept has different names in different parts of the console.** I'll point these out.
- **Copy-pasting from this doc** sometimes pastes wrong characters (smart quotes). If a command fails, retype the suspicious characters.

---

# Phase 1 — Foundations and Terraform state backend

**Estimated time: 8-10 hours for a first-time AWS user**

## What you'll have at the end of Phase 1

- Working AWS account with MFA on root
- An IAM admin user `terraform-admin` for daily use
- Cost alarms at $3 and $10, plus a $5 monthly budget
- Terraform installed and tested
- "Remote state" set up — your Terraform state lives in S3 + DynamoDB, not on your laptop
- Two S3 data buckets created via Terraform
- Code committed to a public GitHub repo

## Concepts you'll need

- **IAM user:** an account inside your AWS account that does daily work. The "root" account is only for setup.
- **MFA (Multi-Factor Authentication):** a second login factor beyond password. Critical on the root account.
- **Access keys:** username + password for the AWS CLI. Format: an access key ID + secret access key.
- **Terraform state:** a file (`.tfstate`) that records what infrastructure Terraform has created. If you lose it, Terraform forgets and creates duplicates.
- **Remote state:** state stored in S3 instead of on your laptop. Survives laptop crashes.
- **Lock table:** a DynamoDB table that prevents two people running Terraform at the same time and corrupting state.

## Steps

### 1.1 — Create dedicated AWS account (45 min)

**What this does:** signs you up for a fresh AWS account that you'll only use for this project.

**Why a dedicated account:** isolates billing. If something goes wrong here, it can't affect a personal AWS account. Also, free-tier credits reset for new accounts.

**How:**

1. Open `aws.amazon.com` in your browser. Click "Create an AWS Account" (top right).
2. Email: use a fresh address. The Gmail trick `youraddress+ghtrends@gmail.com` works — Gmail delivers to your normal inbox but AWS treats it as separate. If you don't use Gmail, just use a real fresh address.
3. Password: generate a 20+ character password in your password manager.
4. Account name: `ghtrends`.
5. Click Continue. Fill in Personal account details (name, address, phone).
6. Credit/debit card: enter it. AWS will charge $1 and refund within a few days. With our alarms, this is the only money you risk.
7. Phone verification: AWS calls or texts you a code. Enter it.
8. Choose **Basic Support — Free** plan. (The other plans cost $29+/month — do not pick.)
9. Wait 2-5 minutes for account activation. You'll get an email confirmation.

**What success looks like:** you can sign into `console.aws.amazon.com` with your root email + password, and you see the AWS Console homepage.

**Save in your password manager:**
- Root email
- Root password
- 12-digit AWS account ID (visible in top-right dropdown after signing in)

### 1.2 — Enable MFA on root user (15 min)

**What this does:** adds a second factor (an authenticator app code) to your root login.

**Why:** the root account has unlimited power. If someone steals the password, MFA blocks them.

**How:**

1. Sign in as root at `console.aws.amazon.com`.
2. Top-right: click your account name → **Security credentials**.
3. Scroll to "Multi-factor authentication (MFA)" → click **Assign MFA device**.
4. Device name: `root-totp`.
5. Choose **Authenticator app**.
6. On your phone, install Google Authenticator, Authy, or your password manager's TOTP feature.
7. Scan the QR code shown by AWS.
8. Enter two consecutive 6-digit codes from the app.
9. Click Add MFA.

**What success looks like:** the security credentials page now shows your MFA device.

**Save in your password manager:** the MFA backup codes if your authenticator showed any.

### 1.3 — Create IAM admin user (30 min)

**What this does:** creates a daily-driver user with admin permissions, separate from root.

**Why:** AWS best practice is to never use root for day-to-day work. Root is for billing and account-level changes only.

**How:**

1. In the AWS Console, search bar at top → type `IAM` → click the IAM service.
2. Left sidebar → **Users** → **Create user** (orange button, top right).
3. User name: `terraform-admin`. Click **Next**.
4. Permissions options: **Attach policies directly**.
5. In the search box, type `AdministratorAccess`. Tick the checkbox next to it.
6. Click **Next** → **Create user**.
7. Click into the user you just created.
8. Tab: **Security credentials** → scroll down to **Access keys** → **Create access key**.
9. Use case: **Command Line Interface (CLI)**.
10. Tick "I understand the above recommendation". Click **Next**.
11. Description tag: `local laptop`. Click **Create access key**.
12. **Now copy both values immediately:**
    - Access key ID (looks like `AKIAIOSFODNN7EXAMPLE`)
    - Secret access key (looks like `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY`)
13. Save these in your password manager. AWS will not show the secret again.

**What success looks like:** the user `terraform-admin` exists with `AdministratorAccess` and one active access key.

### 1.4 — Set up billing alarms (45 min)

**What this does:** AWS will email you if your spending crosses $3 or $10 in a month.

**Why:** the only way to feel safe leaving infrastructure running is knowing you'll be warned before charges accumulate.

**How:**

#### 1.4a — Enable billing alerts (5 min)

1. Top right → click your account name → **Account**.
2. Scroll to **Billing preferences** → click **Edit**.
3. Tick **Receive AWS Free Tier alerts** and **Receive Billing Alerts**.
4. Click **Update**.

**What success looks like:** both checkboxes show as enabled.

#### 1.4b — Switch region to us-east-1 (1 min)

Critical: billing metrics only exist in us-east-1.

1. Top-right region dropdown → **US East (N. Virginia) us-east-1**.
2. Verify the URL or breadcrumb says "us-east-1".

#### 1.4c — Create the $3 alarm (15 min)

1. Search bar → `CloudWatch` → open the service.
2. Left sidebar → **Alarms** → **All alarms** → **Create alarm** (orange button).
3. Click **Select metric** → **Billing** → **Total Estimated Charge** → tick the row with `Currency = USD` → **Select metric**.
4. Statistic: Maximum. Period: 6 hours.
5. Threshold type: Static. Whenever EstimatedCharges is **Greater >** than `3`.
6. Click **Next**.
7. Notification: **In alarm**. SNS topic: **Create new topic**. Name: `billing-alerts`. Email endpoint: your real email. Click **Create topic**.
8. Click **Next**.
9. Alarm name: `billing-alarm-3-usd`. Click **Next** → **Create alarm**.
10. Check your email. AWS sent a "Confirm subscription" message. **Click the confirmation link.** If you skip this, the alarm fires but you never get the email.

#### 1.4d — Create the $10 alarm (5 min)

Same as above but threshold `10` and alarm name `billing-alarm-10-usd`. Reuse the existing `billing-alerts` SNS topic.

#### 1.4e — Create AWS Budget (10 min)

1. Search bar → `Budgets` → open AWS Budgets.
2. **Create budget** → choose **Customize (advanced)** → **Cost budget**.
3. Budget name: `monthly-cap`. Amount: `5` USD.
4. Budget scope: leave defaults.
5. Alerts: at 50% (forecasted), 80% (actual), 100% (actual). Each alert → email yourself.
6. Create.

**What success looks like:** in CloudWatch → Alarms → All alarms, both billing alarms show "OK". In Budgets, `monthly-cap` exists.

### 1.5 — Install local tools (45 min)

**What this does:** installs Terraform, AWS CLI, Git, Docker, and Make on your laptop.

**Why:** you'll use all of these constantly.

**How (Windows):**

1. Install Chocolatey package manager: open PowerShell as Administrator, run the install command from `chocolatey.org/install`.
2. In an Administrator PowerShell, run:
   ```
   choco install -y terraform awscli git docker-desktop make
   ```
3. Restart your computer (Docker requires it).
4. Open Docker Desktop. Wait until the whale icon in the system tray is steady (not animating).

**How (Mac):**

1. Install Homebrew from `brew.sh`.
2. Install the rest:
   ```
   brew install tfenv awscli git docker make
   tfenv install 1.6.6
   tfenv use 1.6.6
   ```
3. Install Docker Desktop manually from `docker.com`.
4. Open Docker Desktop. Wait for the whale icon.

**How (Linux):**

1. Follow HashiCorp's apt repo instructions for Terraform 1.6+.
2. Install the rest:
   ```
   sudo apt install -y awscli git docker.io make
   sudo usermod -aG docker $USER
   ```
3. Log out and back in (the docker group change needs a fresh session).

**Verify:**

```
terraform version    # should be 1.6 or higher
aws --version        # should be aws-cli/2.x
git --version
docker --version
docker run hello-world    # should print a "Hello from Docker!" message
make --version
```

**What success looks like:** all five commands print versions and `docker run hello-world` succeeds.

### 1.6 — Configure AWS CLI profile (15 min)

**What this does:** tells the AWS CLI which AWS account to talk to.

**How:**

1. Open a fresh terminal.
2. Run:
   ```
   aws configure --profile ghtrends
   ```
3. Paste each value when prompted:
   - AWS Access Key ID: (the AKIA... key from Step 1.3)
   - AWS Secret Access Key: (the long secret from Step 1.3)
   - Default region name: `us-east-1`
   - Default output format: `json`
4. Test:
   ```
   aws sts get-caller-identity --profile ghtrends
   ```

**What success looks like:** the test command prints something like:
```json
{
    "UserId": "AIDA...",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/terraform-admin"
}
```

If you see `Unable to locate credentials`: you typed something wrong, redo step 2.

### 1.7 — Configure local project files (10 min)

**What this does:** tells the project what AWS account, region, and profile to use.

**How:**

1. In the project root, copy `.env.example` to `.env`:
   ```
   cp .env.example .env
   ```
2. Open `.env` in your editor. Fill in:
   - `AWS_ACCOUNT_ID=` (your 12-digit account ID from the console)
3. Leave `TFSTATE_BUCKET=` blank for now — we'll fill it after the next step.

### 1.8 — Bootstrap Terraform state backend (1 hour)

**What this does:** creates the S3 bucket + DynamoDB table where Terraform will store its state.

**Why this is "bootstrap" and not Terraform itself:** Terraform needs the state bucket to exist *before* `terraform init` runs. Chicken-and-egg. So we create it once via shell script.

**How:**

1. Make the bootstrap script runnable:
   ```
   chmod +x bootstrap/create_state_backend.sh
   ```
   On Windows: skip this, Git Bash handles it.

2. Run:
   ```
   make bootstrap
   ```
   You'll see:
   - It prompts you to confirm. Type `y`.
   - It creates the S3 state bucket (named `ghtrends-tfstate-<your-account-id>`).
   - It enables versioning, encryption, and blocks public access on it.
   - It creates a DynamoDB table called `tfstate-locks`.

3. The script ends by printing a summary like:
   ```
   Next steps:
     1. Open terraform/backend.tf
     2. Replace <TFSTATE_BUCKET> with: ghtrends-tfstate-123456789012
     3. Add to your .env file:
          TFSTATE_BUCKET=ghtrends-tfstate-123456789012
     4. Run: make tf-init
   ```

4. Open `terraform/backend.tf`. Replace `<TFSTATE_BUCKET>` with the bucket name from the script's output.

5. Open `.env`. Set `TFSTATE_BUCKET=` to the same bucket name.

**What success looks like:**
- In the AWS Console → S3 → you see the bucket `ghtrends-tfstate-<id>`.
- In the Console → DynamoDB → Tables → you see `tfstate-locks`.
- `terraform/backend.tf` no longer has `<TFSTATE_BUCKET>` placeholder.

**If you see `BucketAlreadyExists`:** someone else has the bucket name. Edit your `PROJECT_NAME` in `.env` to something unique like `ghtrends-yourname` and re-run.

### 1.9 — Initialize Terraform (15 min)

**What this does:** Terraform connects to the remote state backend and downloads provider plugins.

**How:**

```
make tf-init
```

You should see lines like:
```
Initializing the backend...
Successfully configured the backend "s3"!
Initializing provider plugins...
- Installing hashicorp/aws v5.40.0...
Terraform has been successfully initialized!
```

**If you see `Error refreshing state: AccessDenied`:** your AWS profile doesn't match. Verify with `aws sts get-caller-identity --profile ghtrends`.

### 1.10 — First apply: create the data buckets (1 hour)

**What this does:** Terraform creates two S3 buckets for our data.

**How:**

1. Plan first (this just shows what will happen, doesn't change anything):
   ```
   make tf-plan
   ```
   Read every line. Near the bottom you should see "Plan: 9 to add, 0 to change, 0 to destroy". Those 9 are:
   - 2 S3 buckets (raw, lake)
   - 2 bucket versioning configs
   - 2 bucket encryption configs
   - 2 bucket public access blocks
   - 1 lifecycle config (raw only)

   If the count is off by 1-2, scroll through the plan and confirm each `will be created` line matches the list above. Don't apply if any line shows `will be destroyed` or `will be replaced` — that means something pre-existing is conflicting.

2. Apply:
   ```
   make tf-apply
   ```
   Type `yes` when prompted. Wait 30-60 seconds.

3. Verify in Console → S3 → you see:
   - `ghtrends-dev-raw`
   - `ghtrends-dev-lake`
   Both should show "Bucket Versioning: Enabled".

**What success looks like:** Terraform prints "Apply complete! Resources: 9 added".

### 1.11 — Verify destroy/recreate cycle (45 min)

**What this does:** proves you can tear down and recreate everything cleanly.

**Why:** if you can't destroy, you can't experiment safely. Better to find this issue now.

**How:**

1. Tear it down:
   ```
   make tf-destroy
   ```
   Type `yes` when prompted. Wait 30 seconds.

2. Check Console → S3 — both buckets are gone.

3. Recreate:
   ```
   make tf-apply
   ```
   Buckets come back, identical to before.

**If destroy fails with "BucketNotEmpty":** the bucket has versioned objects. Edit `terraform/modules/s3_data_lake/main.tf`, add `force_destroy = true` to each `aws_s3_bucket` resource. Re-run destroy.

### 1.12 — Initial git commit and push (45 min)

**What this does:** publishes the project to GitHub.

**How:**

1. Go to `github.com/new` → create a public repo named `ghtrends`. Don't add a README, .gitignore, or license — we already have them.
2. From project root:
   ```
   git init
   git add .
   git status
   ```
   Look at the `git status` output carefully. **You should NOT see:**
   - `.env`
   - any `*.tfstate` files
   - `.terraform/` directory
   If you do, your `.gitignore` is wrong. Fix before continuing.

3. Commit and push:
   ```
   git commit -m "Phase 1: foundations and state backend"
   git branch -M main
   git remote add origin git@github.com:YOUR_USERNAME/ghtrends.git
   git push -u origin main
   ```

4. Open the repo URL on GitHub. Click around. Verify nothing sensitive is visible.

**What success looks like:** the GitHub repo shows your code with no `.env` and no AWS keys.

## Verification — Phase 1 done means

- [ ] `aws sts get-caller-identity --profile ghtrends` returns your account info
- [ ] CloudWatch alarms `billing-alarm-3-usd` and `billing-alarm-10-usd` exist in us-east-1, status "OK"
- [ ] AWS Budget `monthly-cap` exists with email alerts set up
- [ ] You confirmed both SNS subscription emails (check inbox + spam)
- [ ] `make tf-apply` and `make tf-destroy` both succeed
- [ ] Public GitHub repo at `github.com/YOUR_USERNAME/ghtrends` has the code
- [ ] You can answer aloud: "Where is my Terraform state stored, and why DynamoDB?"

If any box is unchecked, do not start Phase 2.

## Troubleshooting Phase 1

- **"Unable to locate credentials"**: check `aws configure list --profile ghtrends`. The access key column should not say `<not set>`.
- **"AccessDenied" during `make bootstrap`**: your IAM user is missing `AdministratorAccess`. Re-attach it.
- **"BucketAlreadyExists"**: bucket name globally taken. Change `PROJECT_NAME` in `.env`.
- **Terraform hangs on apply**: probably waiting for state lock. Open Console → DynamoDB → `tfstate-locks` → check Items. If a stale lock exists, delete it (carefully).
- **Console "session expired"**: AWS sessions are short. Just re-sign-in.
- **Docker on Windows refuses to start**: ensure WSL 2 is enabled. `wsl --install` from PowerShell, then restart.

## What you must NOT do in Phase 1

- Don't write the Lambda yet
- Don't loosen S3 public access blocks
- Don't skip the destroy/recreate verification
- Don't commit `.env` or `*.tfstate` to git
- Don't keep the access keys you generated in plain text anywhere outside your password manager

---

# Phase 2 — Ingest Lambda

**Estimated time: 14-18 hours for first-time Lambda use**

## What you'll have at the end of Phase 2

- A Lambda function that downloads one hour of GH Archive data and writes Parquet to S3
- An EventBridge cron that triggers the Lambda hourly
- 14 days × 24 hours = 336 Parquet files in S3, ready to query in Phase 3

## Concepts you'll need

- **Lambda:** AWS service that runs your code on demand or on a schedule. No server to manage. Charged per invocation + per millisecond of execution.
- **EventBridge:** AWS scheduler. We'll set "run this Lambda every hour at minute :05".
- **Lambda layer / deployment package:** Lambda needs your code packaged as a zip. Python dependencies (like `pyarrow`) must be inside the zip.
- **Lambda runtime:** the OS + Python version Lambda runs on. Currently Amazon Linux 2 + Python 3.11. Compiled C extensions (like `pyarrow`) must match this exact runtime, otherwise they fail to load.
- **Idempotency:** "running this twice produces the same result as running once". We'll skip files that already exist.

## Steps

### 2.1 — Read the Lambda handler (30 min)

**What this does:** familiarize yourself with the code that will run on Lambda.

**How:**

1. Open `lambda/ingest_gh_archive/handler.py`.
2. Read top to bottom. Focus on:
   - `lambda_handler()` — entry point
   - `_resolve_target_hour()` — figures out which hour to download
   - `_download_with_retry()` — pulls the gzipped file
   - `_iter_events()` — streams JSON lines out of the gzip
   - `_flatten()` — converts nested event JSON to flat columns
   - `_write_parquet()` — uploads to S3
   - `_s3_object_exists()` — idempotency helper
3. Trace one event through the whole flow in your head.

Do not modify anything yet.

### 2.2 — Test the handler locally (1.5 hours)

**What this does:** verifies the code works on your laptop before deploying.

**Why local first:** debugging Lambda is painful. Catch bugs locally where you can use a debugger.

**How:**

1. Create a Python virtual environment:
   ```
   cd lambda/ingest_gh_archive
   python -m venv venv
   source venv/bin/activate    # Windows: venv\Scripts\activate
   pip install -r requirements.txt
   ```

2. Set required environment variables. Pick the section for your terminal:

   **Mac / Linux / Git Bash on Windows:**
   ```
   export RAW_BUCKET=ghtrends-dev-raw
   export AWS_PROFILE=ghtrends
   ```

   **Windows PowerShell** (prompt looks like `PS C:\...>`):
   ```
   $env:RAW_BUCKET = "ghtrends-dev-raw"
   $env:AWS_PROFILE = "ghtrends"
   ```

   **Windows CMD** (prompt looks like `C:\...>`):
   ```
   set RAW_BUCKET=ghtrends-dev-raw
   set AWS_PROFILE=ghtrends
   ```

   To verify they stuck, run `echo $env:AWS_PROFILE` (PowerShell) or `echo $AWS_PROFILE` (Bash) — it should print `ghtrends`.

3. Run for a known good hour. Pick a date **2-3 days before today** so GH Archive has published it:
   ```
   python handler.py 2026-05-04T13:00:00Z
   ```
   Replace `2026-05-04` with whatever "2-3 days ago" is when you run this. Format must be `YYYY-MM-DDTHH:00:00Z`.

4. You should see log output like:
   ```
   2026-05-06 12:00:00 INFO Ingesting GH Archive for hour=2026-04-30T13:00:00+00:00
   2026-05-06 12:00:01 INFO GET https://data.gharchive.org/2026-04-30-13.json.gz (attempt 1)
   2026-05-06 12:00:25 INFO Wrote s3://ghtrends-dev-raw/raw/event_type=WatchEvent/year=2026/month=04/day=30/hour=13/data.parquet (4231 rows)
   2026-05-06 12:00:26 INFO Wrote s3://ghtrends-dev-raw/raw/event_type=PullRequestEvent/year=2026/month=04/day=30/hour=13/data.parquet (1182 rows)
   ```

5. Verify in S3:
   ```
   aws s3 ls s3://ghtrends-dev-raw/raw/event_type=WatchEvent/year=2026/month=04/day=30/hour=13/ --profile ghtrends
   ```
   Should show one `data.parquet` file.

**If GH Archive returns 404:** that hour hasn't published yet. Pick an earlier date.

**If you get `NoCredentialsError`:** check `AWS_PROFILE` is set in this terminal.

### 2.3 — Build the deployment zip (1 hour)

**What this does:** packages the code + dependencies into a zip Lambda can run.

**Why Docker is required:** `pyarrow` has compiled C code that has to match Lambda's exact runtime (Amazon Linux 2 + Python 3.11). If you build the zip on Mac or Windows, it'll fail with `ImportError` when Lambda tries to load it. Docker spins up the official Lambda runtime image and builds inside it.

**How:**

1. Make sure Docker Desktop is running (whale icon steady in system tray).
2. From project root:
   ```
   make lambda-package
   ```
3. Watch the output. You'll see:
   - Pulling the Lambda runtime image (first time only, ~200 MB download).
   - Installing requirements inside the image.
   - Zipping.
   - Final size: 30-60 MB.

4. Verify the zip exists:
   ```
   ls -la lambda/ingest_gh_archive/ingest_gh_archive.zip
   ```

**If Docker complains about pulling the image:** check internet, retry.

**If the zip is 200+ MB:** something installed wrong. Delete `lambda/ingest_gh_archive/build/` and the zip, then retry.

### 2.4 — Create the Terraform module for the Lambda (5 hours)

**What this does:** writes Terraform code that creates the IAM role, the Lambda function, the CloudWatch log group, and the EventBridge cron.

**Why Terraform:** clicking it manually would mean you can't reproduce or version-control the setup.

**How:**

1. Create file `terraform/modules/lambda_ingest/main.tf`. Use the structure of `terraform/modules/s3_data_lake/main.tf` as a template.

2. The module should accept these variables:
   - `project_name` (string)
   - `env` (string)
   - `raw_bucket_name` (string)
   - `raw_bucket_arn` (string)

3. The module should create:
   - **IAM role** (`aws_iam_role`) named `${project_name}-${env}-ingest-lambda-role`. Trust policy: `lambda.amazonaws.com` can assume it.
   - **IAM policy** (`aws_iam_role_policy`) attached to the role with permission to:
     - `s3:PutObject` and `s3:HeadObject` on `${raw_bucket_arn}/*`
     - `logs:CreateLogGroup`, `logs:CreateLogStream`, `logs:PutLogEvents` (for CloudWatch logs)
   - **Lambda function** (`aws_lambda_function`):
     - `function_name = "${project_name}-${env}-ingest"`
     - `runtime = "python3.11"`
     - `handler = "handler.lambda_handler"`
     - `memory_size = 512`
     - `timeout = 300`
     - `filename = "${path.module}/../../../lambda/ingest_gh_archive/ingest_gh_archive.zip"`
     - `source_code_hash = filebase64sha256(...)` — pointing at the same zip
     - `environment.variables.RAW_BUCKET = var.raw_bucket_name`
   - **CloudWatch log group** (`aws_cloudwatch_log_group`):
     - `name = "/aws/lambda/${project_name}-${env}-ingest"`
     - `retention_in_days = 14` (otherwise logs accumulate forever and cost money)
   - **EventBridge rule** (`aws_cloudwatch_event_rule`):
     - `schedule_expression = "cron(5 * * * ? *)"` (5 minutes after every hour)
   - **EventBridge target** (`aws_cloudwatch_event_target`):
     - Points the rule at the Lambda
   - **Lambda permission** (`aws_lambda_permission`):
     - Allows EventBridge to invoke the Lambda

4. Output the Lambda ARN.

5. In `terraform/main.tf`, uncomment the `module "ingest_lambda"` block.

6. Run:
   ```
   make tf-plan
   ```
   Should say "Plan: 7-8 to add". Read every line.

7. Apply:
   ```
   make tf-apply
   ```
   Type `yes` when prompted.

**If you get `InvalidParameterValue: filename`:** the zip path is wrong. Check the relative path resolves correctly.

**If `tf-apply` succeeds but the Lambda isn't visible:** check the region. Both Console and Terraform must use us-east-1.

### 2.5 — Test the deployed Lambda (30 min)

**What this does:** invokes the Lambda once from your laptop to confirm it works in AWS.

**How:**

1. Invoke the function from your laptop.

   **PowerShell (Windows)** — write the payload to a file first, then read it via `file://`. Do NOT try to pass JSON inline; PowerShell strips quotes when handing args to `aws.exe`.
   ```
   '{"timestamp": "2026-05-04T14:00:00Z"}' | Set-Content -Path payload.json -Encoding ascii
   aws lambda invoke --function-name ghtrends-dev-ingest --payload file://payload.json --cli-binary-format raw-in-base64-out --profile ghtrends response.json
   ```
   Then `Remove-Item payload.json` to clean up.

   **Bash (Mac, Linux, Git Bash on Windows):**
   ```
   aws lambda invoke \
     --function-name ghtrends-dev-ingest \
     --payload '{"timestamp": "2026-05-04T14:00:00Z"}' \
     --cli-binary-format raw-in-base64-out \
     --profile ghtrends \
     response.json
   ```

   Replace `2026-05-04` with a date 2-3 days before today.

   You should see `"StatusCode": 200` printed back. That confirms AWS accepted the call.

2. Check what the Lambda returned (Lambda's own response, written to `response.json`):

   **PowerShell/CMD:**
   ```
   Get-Content response.json
   ```

   **Bash:**
   ```
   cat response.json
   ```

   Should be JSON like `{"statusCode": 200, "counts": {"total": 56234, "WatchEvent": 4231, "PullRequestEvent": 1182}, ...}`.

3. Check S3 has a new file:
   ```
   aws s3 ls s3://ghtrends-dev-raw/raw/event_type=WatchEvent/year=2026/month=04/day=30/hour=14/ --profile ghtrends
   ```

4. Check the CloudWatch logs:
   - Console → CloudWatch → Log groups → `/aws/lambda/ghtrends-dev-ingest` → click into the latest log stream.
   - You should see the same lines you saw in step 2.2.

**If the Lambda times out (300 sec):** the file is bigger than usual. In `terraform/modules/lambda_ingest/main.tf`, bump `timeout = 600`. Re-apply.

**If you see `ImportError: pyarrow`:** the zip was built outside Docker. Re-run `make lambda-package`.

### 2.6 — Backfill last 14 days (3 hours)

**What this does:** runs the Lambda 336 times to populate S3 with 14 days × 24 hours of data.

**Why 14 days:** Phase 3 (Athena) needs data to query. Phase 5 (embeddings) needs at least 30 days for "trending" calculation, but 14 days is enough to verify the pipeline.

**How:**

1. Save this script as `scripts/backfill.sh`:
   ```bash
   #!/usr/bin/env bash
   set -e
   for d in {1..14}; do
     for h in {0..23}; do
       DT=$(date -u -d "${d} days ago ${h}:00:00" '+%Y-%m-%dT%H:00:00Z')
       echo "Invoking for $DT"
       aws lambda invoke \
         --function-name ghtrends-dev-ingest \
         --payload "$(printf '{"timestamp":"%s"}' "$DT")" \
         --cli-binary-format raw-in-base64-out \
         --profile ghtrends \
         /tmp/resp.json > /dev/null
     done
   done
   ```

2. Run it:
   ```
   chmod +x scripts/backfill.sh
   ./scripts/backfill.sh
   ```

3. Wait ~30-45 min. Each invocation takes 30-60 seconds.

4. Verify count:
   ```
   aws s3 ls s3://ghtrends-dev-raw/raw/ --recursive --profile ghtrends | wc -l
   ```
   Should be ~600-700 files (14 days × 24 hours × 2 event types, minus a few for hours with no PRs).

**If invocations fail with `TooManyRequestsException`:** Lambda concurrency limit. Add `sleep 1` to the loop.

## Verification — Phase 2 done means

- [ ] Lambda runs successfully when invoked manually
- [ ] EventBridge cron is active (visible in EventBridge Console)
- [ ] At least 600 Parquet files exist in `s3://ghtrends-dev-raw/raw/`
- [ ] CloudWatch log group has 14-day retention
- [ ] Re-running for the same hour skips with "Skipping existing s3://..."
- [ ] You can answer: "Why does the Lambda run 5 minutes after the hour, not on the hour?"

## Troubleshooting Phase 2

- **`ImportError: pyarrow` in Lambda logs:** zip not built in Docker. Re-run `make lambda-package`.
- **`AccessDenied` on `s3:PutObject`:** IAM policy is missing the bucket ARN. Edit the module's policy.
- **`Task timed out after 300 seconds`:** bump Lambda timeout to 600. Some hours have huge files.
- **`Skipping existing s3://...`** during backfill: that's fine — idempotency working.
- **Backfill skips half the hours:** check the date math in your shell. Some shells handle `date` differently. On Mac use `date -u -v-${d}d -v${h}H -v0M -v0S '+%Y-%m-%dT%H:00:00Z'`.

## What you must NOT do in Phase 2

- Don't add Step Functions
- Don't expand the event-type list beyond Watch and PullRequest
- Don't skip the local test before deploying

---

# Phase 3 — Glue Crawler and Athena

**Estimated time: 10-12 hours**

## What you'll have at the end of Phase 3

- A Glue Catalog database `ghtrends_lake` with two tables (`watch_events`, `pull_request_events`)
- An automated Glue Crawler that re-discovers new partitions daily
- Athena workgroup configured with strict cost limits
- Working SQL queries against the data

## Concepts you'll need

- **Glue Catalog:** like a database catalog (schemas + tables) but the actual data lives in S3, not in a database. The catalog is just metadata: "table X has these columns and lives at this S3 path".
- **Glue Crawler:** scans S3 paths, infers schema from Parquet files, and writes the result into the Glue Catalog. Run once at setup, then on a daily schedule to pick up new partitions.
- **Athena:** runs SQL against the files in S3, using the Glue Catalog for schema. Pay per byte scanned.
- **Workgroup:** a "container" for Athena queries that lets you set cost limits and define where query results go.
- **Partition pruning:** if your query has `WHERE year=2026 AND month=4`, Athena only reads files in that partition. If your query has no date filter, it reads everything. Always filter.

## Steps

### 3.1 — Create the Glue catalog module (2 hours)

Create `terraform/modules/glue_catalog/main.tf`:

```hcl
variable "project_name"    { type = string }
variable "env"             { type = string }
variable "raw_bucket_name" { type = string }

resource "aws_glue_catalog_database" "lake" {
  name        = "${var.project_name}_lake"
  description = "Catalog over partitioned Parquet from GH Archive"
}

# IAM role for the crawler
resource "aws_iam_role" "crawler" {
  name = "${var.project_name}-${var.env}-crawler-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "glue.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "crawler_glue" {
  role       = aws_iam_role.crawler.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy" "crawler_s3" {
  role = aws_iam_role.crawler.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["s3:GetObject", "s3:ListBucket"]
      Resource = [
        "arn:aws:s3:::${var.raw_bucket_name}",
        "arn:aws:s3:::${var.raw_bucket_name}/*"
      ]
    }]
  })
}

resource "aws_glue_crawler" "raw" {
  name          = "${var.project_name}-${var.env}-crawler"
  database_name = aws_glue_catalog_database.lake.name
  role          = aws_iam_role.crawler.arn

  s3_target {
    path = "s3://${var.raw_bucket_name}/raw/"
  }

  schedule = "cron(0 1 * * ? *)"   # 1 AM UTC daily

  configuration = jsonencode({
    Version = 1.0
    CrawlerOutput = {
      Partitions = { AddOrUpdateBehavior = "InheritFromTable" }
    }
  })
}

output "database_name" { value = aws_glue_catalog_database.lake.name }
```

Wire into `terraform/main.tf`. Apply.

### 3.2 — Run the crawler manually for the first time (15 min)

**Why manually:** the schedule won't fire until 1 AM. Run now to populate the catalog.

**How:**

1. Console → Glue → Crawlers → click `ghtrends-dev-crawler` → **Run crawler**.
2. Wait 1-2 minutes. Status: Starting → Running → Stopping → Ready.
3. When done, the crawler info shows "Tables added: 2".
4. Console → Glue → Databases → `ghtrends_lake` → click → you should see `watch_events` and `pull_request_events`.
5. Click into `watch_events`. The schema should show columns `id`, `type`, `actor_id`, etc.

**If 0 tables:** the crawler couldn't find files. Verify the S3 path in step 2.6 had data.

**If column types look wrong** (e.g. `created_at` came in as `string` not `timestamp`): we'll fix in dbt staging in Phase 4. Don't fight the crawler.

### 3.3 — Configure Athena workgroup (30 min)

**Why:** without limits, one bad query can scan terabytes and cost $20+. Workgroup limits cap that.

**How:**

1. Console → Athena → Workgroups → `primary` → **Edit**.
2. Query result location: `s3://ghtrends-dev-lake/athena_results/`. Encryption: SSE_S3.
3. Engine version: 3 (default). Confirm it says v3, not v2.
4. **Per query data scanned limit: 1 GB**.
5. **Workgroup data scanned limit: 10 GB per day**.
6. Save.

**What success looks like:** the workgroup detail page shows both limits.

### 3.4 — Run your first Athena query (15 min)

1. Console → Athena → Query editor.
2. Top-left: select database `ghtrends_lake`.
3. In the editor, type:
   ```sql
   SELECT count(*) FROM ghtrends_lake.watch_events;
   ```
4. Click **Run**.
5. Should return a single number > 1M after a few seconds. Bottom panel shows "Data scanned: ~XX MB".

**If Athena says "no permission":** your IAM user has `AdministratorAccess`, so this shouldn't happen. If it does, your region is wrong.

**If "Table 'watch_events' does not exist":** crawler didn't run. Re-run from step 3.2.

### 3.5 — Build the query suite (4 hours)

Three example queries are already in `analysis/queries/`. Add four more:

- `04_top_organizations.sql` — top organizations by total event volume in last 30 days
- `05_active_users.sql` — top contributors by PR count
- `06_hourly_star_distribution.sql` — what hour of UTC do stars happen most?
- `07_emerging_repos.sql` — repos that crossed 100 stars/day for the first time

For each query:
- Run it in Athena, save to `analysis/queries/`
- Add a comment header: estimated runtime, bytes scanned, what finding it produces
- Screenshot the top 10 results, save in `analysis/findings/` as PNG

### 3.6 — Sanity-check costs (15 min)

1. Athena → Query history → look at "Data scanned" for each of your queries today.
2. Total should be < 1 GB.
3. If you see one query at 5+ GB, you forgot partition pruning. Add date filters.

## Verification — Phase 3 done means

- [ ] Glue Crawler ran and created two tables
- [ ] Athena `SELECT count(*) FROM watch_events` returns a number
- [ ] Athena workgroup has 1 GB/query and 10 GB/day limits
- [ ] All 7 query files run successfully
- [ ] Each query scans < 500 MB
- [ ] You have 7 PNG screenshots in `analysis/findings/`
- [ ] You can answer: "What's the difference between the Glue Catalog and the actual data?"

## Troubleshooting Phase 3

- **Crawler created column type mismatches**: edit the table manually in Glue (Console → table → Edit schema). Or fix in dbt staging.
- **Query takes minutes to run**: missing partition predicate. Add `WHERE year = X AND month = Y AND day = Z`.
- **"Insufficient Lake Formation permissions"**: AWS turned on Lake Formation by accident. Console → Lake Formation → Administrative roles → grant your user.

## What you must NOT do in Phase 3

- Don't try to use Iceberg
- Don't enrich with GitHub API yet (Phase 5)

---

# Phase 4 — dbt-core single mart

**Estimated time: 12-14 hours**

## What you'll have at the end of Phase 4

- A dbt project that connects to Athena
- Three layers: staging (views), intermediate (views), marts (table)
- Tests that run as part of `dbt build`
- A public dbt docs site on GitHub Pages
- A nightly GitHub Actions workflow that runs `dbt build`

## Concepts you'll need

- **dbt:** SQL-based transformation tool. You write `SELECT` queries, dbt manages dependencies, materialization, and testing.
- **Model:** a single `.sql` file. dbt runs it and writes the result somewhere.
- **Materialization:** how dbt stores the model output. `view` = just a view. `table` = actual table written to S3 + Glue.
- **Source:** a table that already exists (the Glue tables from Phase 3). dbt reads from sources but doesn't manage them.
- **Staging / Intermediate / Marts:** convention. Staging cleans column names. Intermediate joins/aggregates. Marts are what dashboards query.
- **dbt test:** assertions on data ("this column should never be null").

## Steps

### 4.1 — Install dbt locally (30 min)

```
python -m venv .venv-dbt
source .venv-dbt/bin/activate
pip install dbt-athena-community==1.7.2
dbt --version
```

Should print `dbt-athena: 1.7.2`.

### 4.2 — Configure dbt profile (30 min)

dbt looks for credentials in `~/.dbt/profiles.yml`.

1. Create the directory:
   ```
   mkdir -p ~/.dbt
   ```
2. Copy the example:
   ```
   cp dbt/profiles.yml.example ~/.dbt/profiles.yml
   ```
3. Open `~/.dbt/profiles.yml`. Verify:
   - `aws_profile_name: ghtrends`
   - `s3_staging_dir: s3://ghtrends-dev-lake/athena_results/`
   - `region_name: us-east-1`

### 4.3 — Verify connection (15 min)

```
cd dbt
dbt debug
```

Should print "All checks passed!".

If it fails: usually a wrong AWS profile. Run `aws sts get-caller-identity --profile ghtrends` to verify.

### 4.4 — Read the existing models (1 hour)

Open and read top to bottom:

- `dbt/models/staging/_sources.yml` — declares the Glue tables as dbt sources
- `dbt/models/staging/stg_watch_events.sql`
- `dbt/models/staging/stg_pull_request_events.sql`
- `dbt/models/intermediate/int_repo_daily_activity.sql`
- `dbt/models/marts/fct_repo_trends_daily.sql`

Trace the dependency graph in your head: sources → staging → intermediate → marts.

### 4.5 — Run the build (1 hour)

```
dbt deps     # install dbt_utils package
dbt build
```

`dbt build` runs all models and all tests. You should see lines like:

```
1 of 7 OK created sql view model ghtrends_lake.stg_watch_events
2 of 7 OK created sql view model ghtrends_lake.stg_pull_request_events
3 of 7 OK created sql view model ghtrends_lake.int_repo_daily_activity
4 of 7 OK created sql table model ghtrends_lake.fct_repo_trends_daily
5 of 7 PASS not_null_fct_repo_trends_daily_repo_id
...
Completed successfully
```

If a query fails, dbt prints the SQL it tried to run. Copy that SQL into the Athena editor and debug there.

### 4.6 — Add a custom test (1 hour)

Create `dbt/tests/assert_no_future_dates.sql`:

```sql
SELECT * FROM {{ ref('fct_repo_trends_daily') }}
WHERE event_date > current_date
```

This is a "singular test" — it should return zero rows. If it returns any rows, dbt fails.

Run:
```
dbt test
```

All tests should pass.

### 4.7 — Generate dbt docs site (3 hours)

dbt can generate a static HTML site documenting your project.

1. Generate and serve:
   ```
   dbt docs generate
   dbt docs serve   # opens at localhost:8080
   ```
2. Click around. You'll see lineage graphs, column descriptions, tests.
3. Stop the server (Ctrl-C).
4. Push the static site to GitHub Pages:
   ```
   cd target
   git init
   git add .
   git commit -m "dbt docs"
   git branch -M gh-pages
   git remote add origin git@github.com:YOU/ghtrends.git
   git push -f origin gh-pages
   cd ..
   ```
5. On GitHub: repo Settings → Pages → Source: `gh-pages` branch.
6. Wait 1-2 minutes. Your docs are at `https://YOU.github.io/ghtrends/`.

### 4.8 — Schedule daily dbt run via GitHub Actions (5 hours)

**Why GitHub Actions:** runs dbt nightly without needing an EC2.

**How:**

1. Set up an OIDC role in AWS that GitHub Actions can assume. Add a new Terraform module `terraform/modules/github_oidc/main.tf` that creates the IAM role with trust policy `repo:YOU/ghtrends:*`.
2. Create `.github/workflows/dbt-run.yml`:
   - Runs nightly via `cron`
   - Configures AWS credentials via OIDC
   - Sets up Python + installs dbt
   - Writes a `~/.dbt/profiles.yml` from a GitHub Secret
   - Runs `dbt build`
3. Push and verify the Actions tab shows a successful run.

## Verification — Phase 4 done means

- [ ] `dbt build` runs end-to-end with all tests passing
- [ ] Mart row counts match raw aggregates (within 0.1%)
- [ ] Public dbt docs site live at `YOU.github.io/ghtrends`
- [ ] Nightly GitHub Actions dbt run completes successfully
- [ ] You can answer: "What's the difference between staging, intermediate, and mart layers?"

## Troubleshooting Phase 4

- **`dbt-athena` materializing as the wrong type**: check `dbt_project.yml` and your model's `{{ config(...) }}` block don't conflict.
- **Workgroup mismatch**: `dbt_project.yml` and `profiles.yml` must point to the same Athena workgroup.
- **OIDC role assume fails**: the trust policy `sub` claim is exact format-sensitive. Use `repo:YOU/ghtrends:ref:refs/heads/main` or `repo:YOU/ghtrends:*`.

## What you must NOT do in Phase 4

- Don't add incremental models. Full refresh is enough.
- Don't add more marts (one mart, multiple queries).

---

# Phase 5 — Embeddings (offline) and S3 vector index

**Estimated time: 12-14 hours**

## What you'll have at the end of Phase 5

- 500-1000 trending repos embedded with sentence-transformers
- Two files in S3: `vectors.npy` and `repos.parquet`
- A test script that confirms search returns sensible results

## Concepts you'll need

- **Embedding:** a fixed-length numeric vector (here: 384 floats) representing a piece of text. Similar texts have similar vectors.
- **sentence-transformers:** a Python library wrapping pre-trained transformer models. We use `all-MiniLM-L6-v2` (small, fast, good enough).
- **Cosine similarity:** the angle between two vectors. Range: -1 to 1. Higher = more similar.
- **Why numpy and not pgvector:** for ~500 vectors at 384 dims, numpy's in-memory dot product takes microseconds. pgvector adds infrastructure with no speed benefit at this scale.

## Steps

### 5.1 — Read the embedding script (30 min)

Open `embeddings/embed_repos.py`. The flow:

1. Athena query for top N repos by stars in last 30 days
2. For each: call GitHub API to get description and language
3. Encode descriptions with sentence-transformers
4. Save vectors and metadata to S3

Open `embeddings/test_search.py`. The flow:

1. Load vectors and metadata from S3
2. Encode the query with sentence-transformers
3. Numpy dot product against all vectors
4. Return top K

### 5.2 — Generate a GitHub PAT (10 min)

**Why:** GitHub limits unauthenticated API calls to 60/hour. With a PAT, you get 5000/hour.

**How:**

1. Open `github.com/settings/tokens` → **Generate new token (classic)**.
2. Note: `ghtrends-embed`. Expiration: 90 days.
3. Scopes: leave all unchecked (we only need public read).
4. Generate. **Copy the token.**
5. Save in `.env`: `GITHUB_PAT=ghp_...`.

### 5.3 — Local setup (30 min)

```
cd embeddings
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

The first time, `pip install` takes ~5 min (downloading torch, sentence-transformers).

Set environment:
```
export ATHENA_OUTPUT_S3=s3://ghtrends-dev-lake/athena_results/
export EMBEDDINGS_BUCKET=ghtrends-dev-lake
export GITHUB_PAT=ghp_...
export AWS_PROFILE=ghtrends
```

### 5.4 — Run the embedding job (4 hours wall clock)

```
python embed_repos.py --top 500
```

What happens:

1. Athena query. Takes ~10 seconds.
2. GitHub API enrichment. With PAT: ~6 minutes for 500 repos.
3. Loading the model. First run downloads ~90 MB. Takes ~30 seconds.
4. Encoding. ~1-2 minutes on a laptop CPU.
5. Save to S3.

Total: 10-15 minutes for 500 repos.

If you stop midway and re-run, it picks up where it left off (resumable).

### 5.5 — Verify the index (30 min)

```
python test_search.py "data engineering python pipelines"
```

Should print 10 repos with similarity scores. Eyeball the top 5 — do they look related to data engineering / Python? If yes, the index works.

Try other queries:
- "machine learning"
- "react frontend"
- "rust low level"

If results look random, something's wrong (model loading, encoding mismatch).

### 5.6 — Document the design choice (1 hour)

In your `docs/ARCHITECTURE.md`, add a paragraph explaining why you chose numpy over pgvector. This is the interview answer.

### 5.7 — Optional: bump to 1000 repos (2 hours)

If 500 felt thin in your tests, re-run with `--top 1000`.

## Verification — Phase 5 done means

- [ ] `vectors.npy` in S3 with shape (500, 384) or (1000, 384)
- [ ] `repos.parquet` has matching row count
- [ ] `test_search.py` returns sensible results for at least 3 different queries
- [ ] No Postgres, no pgvector, no EC2
- [ ] You can answer: "Why didn't you use a vector database?"

## Troubleshooting Phase 5

- **`401 Unauthorized` from GitHub API**: PAT is wrong. Regenerate.
- **`OSError: [Errno 28] No space left on device`**: model download exhausted /tmp. Use `TRANSFORMERS_CACHE=/tmp/sbert_cache` or pip install in a venv with more space.
- **Search returns the same results for any query**: model isn't loading. Check `python -c "from sentence_transformers import SentenceTransformer; m = SentenceTransformer('all-MiniLM-L6-v2'); print(m.encode('test')[:3])"` works.

## What you must NOT do in Phase 5

- Don't add pgvector
- Don't try to embed 10K repos
- Don't deploy the model to a server

---

# Phase 6 — Streamlit Community Cloud + demo + findings

**Estimated time: 10-12 hours**

## What you'll have at the end of Phase 6

- A public Streamlit app live at `<yourapp>.streamlit.app`
- 90-second Loom video embedded in your README
- 5 documented findings with screenshots
- 3-5 LinkedIn post drafts

## Concepts you'll need

- **Streamlit Community Cloud:** free hosting for Streamlit apps connected to a GitHub repo. 1 GB RAM limit. App sleeps when idle (30s cold start).
- **Streamlit secrets:** TOML config the app reads instead of environment variables.

## Steps

### 6.1 — Test Streamlit locally (2 hours)

```
cd streamlit
pip install -r requirements.txt
export ATHENA_OUTPUT_S3=s3://ghtrends-dev-lake/athena_results/
export EMBEDDINGS_BUCKET=ghtrends-dev-lake
export AWS_PROFILE=ghtrends
streamlit run app.py
```

Open `localhost:8501`. Verify:

- **Trends** page loads charts (may take 5-10 sec for Athena queries)
- **Search** page loads. Type a query. Get results.
- **About** page loads.

### 6.2 — Create a read-only IAM user (1 hour)

**Why:** Streamlit Cloud needs AWS keys to read S3 + Athena. Don't reuse `terraform-admin` keys (way too much power).

**How:**

1. Add a Terraform module `terraform/modules/streamlit_reader/main.tf` that creates:
   - IAM user `streamlit-reader`
   - Inline policy allowing `s3:GetObject` on the lake bucket and `athena:StartQueryExecution`, `athena:GetQueryResults` on the workgroup
   - Access keys for the user
   - Output the access key ID + secret (via Terraform output marked sensitive)
2. Apply.
3. From `terraform output -raw streamlit_reader_access_key_id` and `terraform output -raw streamlit_reader_secret`, save the values for step 6.4.

### 6.3 — Sign up for Streamlit Community Cloud (15 min)

1. Open `share.streamlit.io`. Sign in with GitHub.
2. Authorize the app to see your repos.

### 6.4 — Deploy the app (1 hour)

1. **New app** → connect to repo `ghtrends`.
2. Branch: `main`. Main file path: `streamlit/app.py`.
3. Python version: `3.11`.
4. **Advanced settings → Secrets** → paste:
   ```toml
   AWS_ACCESS_KEY_ID = "AKIA..."
   AWS_SECRET_ACCESS_KEY = "wJalr..."
   AWS_DEFAULT_REGION = "us-east-1"
   ATHENA_OUTPUT_S3 = "s3://ghtrends-dev-lake/athena_results/"
   EMBEDDINGS_BUCKET = "ghtrends-dev-lake"
   ```
   Use the keys from step 6.2.
5. **Deploy**. Wait 2-5 min for the first build.

### 6.5 — Test the deployed app (30 min)

1. Open the public URL on your phone. Verify both pages.
2. First Search query may take 30s (model cold-load). Subsequent should be <2s.

If you hit the 1 GB RAM limit (app crashes on Search): drop sentence-transformers in favor of pre-encoded common queries, or try a smaller model like `paraphrase-MiniLM-L3-v2`.

### 6.6 — Polish the README (2 hours)

Replace existing README with:

1. One-paragraph pitch
2. Loom video link (next step)
3. Architecture diagram (Mermaid)
4. Live demo URL
5. Screenshot
6. Stack table
7. Local setup
8. Cost breakdown
9. 5 findings with screenshots
10. License

### 6.7 — Record demo video (3 hours)

Script (~90 seconds):

1. (10s) "I built a serverless data platform on AWS that ingests public GitHub Archive events..."
2. (15s) Architecture diagram
3. (25s) Live: open dashboard, scroll Trends
4. (25s) Live: type semantic search query
5. (15s) "Built with Lambda, S3, dbt-core, sentence-transformers. Operating cost under $2/month."

Record with Loom. Plan for 5-10 takes. Embed in README.

### 6.8 — Findings doc and LinkedIn drafts (2 hours)

`docs/FINDINGS.md` — 5 findings. Each:
- One-sentence headline
- Screenshot
- The SQL query
- One paragraph interpretation

`docs/posts/post-1.md` through `post-5.md` — LinkedIn post drafts. One per finding.

### 6.9 — Pin and announce (15 min)

- GitHub: pin `ghtrends` repo on your profile
- LinkedIn: Featured section → add the project
- Schedule the LinkedIn posts (one per week for 5 weeks)

## Verification — Phase 6 done means

- [ ] Streamlit Cloud URL works from phone, laptop, incognito
- [ ] Trends page loads in <5 sec (after cold start)
- [ ] Search page returns in <2 sec (after cold start)
- [ ] Loom video plays, under 2 min
- [ ] One person reads your README and can describe the project in one sentence
- [ ] Repo pinned on GitHub, project on LinkedIn Featured

## Troubleshooting Phase 6

- **App crashes on Search**: 1 GB RAM exceeded. Smaller model, or precompute common query encodings.
- **`AccessDenied` from Athena in Streamlit logs**: read-only IAM user is missing `glue:GetTable*`. Add to its policy.
- **Streamlit shows old code**: it auto-deploys on push to main. Check the latest commit hash in the bottom-right of the app.
- **Cold start every time**: the app went idle (30 min). Tell recruiters about the warmup time in your README.

## What you must NOT do in Phase 6

- Don't claim numbers you haven't measured. Run `count(*)` first.
- Don't make the demo video longer than 2 minutes.
- Don't skip the friend-review step.
- Don't put `terraform-admin` keys in Streamlit secrets.

---

# Final notes

## When you finish Phase 6

- Tag the repo: `git tag v1.0.0 && git push --tags`
- The Streamlit Cloud URL stays up for free
- Monitor billing for one week to confirm steady-state cost

## What v2 looks like

See `NEXT.md`. Don't start any of those until v1 is shipped, demoed, and on your resume.

## When to ask for help

- Stuck on a step for >2 hours: pause, write down what you tried, ask
- Cost alarm fires: run `make tf-destroy` first, then investigate
- Something works locally but fails on Streamlit Cloud: almost always env var or AWS permissions

Good luck.
