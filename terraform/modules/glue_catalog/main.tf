# Phase 3: Glue Catalog database + crawler.
#
# What this module creates:
#   - A Glue Catalog database called "ghtrends_lake" (think of it as a "schema")
#   - An IAM role the crawler runs under
#   - A Glue Crawler that scans s3://<raw>/raw/ daily and registers tables
#
# After this is applied, you'll trigger the crawler manually once. It will
# find your Parquet files and create two tables in the catalog:
#   - ghtrends_lake.watch_events
#   - ghtrends_lake.pull_request_events
#
# After that, Athena can query them via SELECT statements.

variable "project_name"    { type = string }
variable "env"             { type = string }
variable "raw_bucket_name" { type = string }
variable "raw_bucket_arn"  { type = string }

# ----- Glue Catalog database -----

resource "aws_glue_catalog_database" "lake" {
  name        = "ghtrends_lake"
  description = "Catalog over partitioned Parquet from GH Archive"
}

# ----- IAM role for the crawler -----

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

# AWS-managed policy that gives Glue the permissions it needs to write
# back to the catalog and emit logs.
resource "aws_iam_role_policy_attachment" "crawler_glue" {
  role       = aws_iam_role.crawler.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

# Custom policy that lets the crawler read your raw bucket.
resource "aws_iam_role_policy" "crawler_s3" {
  name = "${var.project_name}-${var.env}-crawler-s3-policy"
  role = aws_iam_role.crawler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:ListBucket",
      ]
      Resource = [
        var.raw_bucket_arn,
        "${var.raw_bucket_arn}/*",
      ]
    }]
  })
}

# ----- The crawler -----

resource "aws_glue_crawler" "raw" {
  name          = "${var.project_name}-${var.env}-crawler"
  database_name = aws_glue_catalog_database.lake.name
  role          = aws_iam_role.crawler.arn
  description   = "Scans s3://${var.raw_bucket_name}/raw/ and registers tables"

  s3_target {
    path = "s3://${var.raw_bucket_name}/raw/"
  }

  # Daily at 1 AM UTC. We'll trigger it manually the first time.
  schedule = "cron(0 1 * * ? *)"

  # Tell the crawler that subdirectories under raw/ are part of partitioning,
  # not separate tables. The "event_type=...", "year=...", etc. directories
  # become partition columns.
  configuration = jsonencode({
    Version = 1.0
    CrawlerOutput = {
      Partitions = { AddOrUpdateBehavior = "InheritFromTable" }
    }
  })
}

# ----- Outputs -----

output "database_name" {
  description = "Name of the Glue Catalog database"
  value       = aws_glue_catalog_database.lake.name
}

output "crawler_name" {
  description = "Name of the Glue Crawler"
  value       = aws_glue_crawler.raw.name
}
