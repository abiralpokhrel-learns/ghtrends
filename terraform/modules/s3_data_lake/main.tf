# Two S3 buckets:
#   raw   - landing zone for Parquet files written by ingest Lambda
#   lake  - holds Glue/dbt catalog data, Athena query results, and the
#           numpy embeddings index built in Phase 5
#
# Both are versioned, encrypted, and block all public access.

variable "project_name" { type = string }
variable "env" { type = string }

locals {
  raw_bucket_name  = "${var.project_name}-${var.env}-raw"
  lake_bucket_name = "${var.project_name}-${var.env}-lake"
}

resource "aws_s3_bucket" "raw" {
  bucket = local.raw_bucket_name
}

resource "aws_s3_bucket" "lake" {
  bucket = local.lake_bucket_name
}

resource "aws_s3_bucket_versioning" "raw" {
  bucket = aws_s3_bucket.raw.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_versioning" "lake" {
  bucket = aws_s3_bucket.lake.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "raw" {
  bucket = aws_s3_bucket.raw.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "lake" {
  bucket = aws_s3_bucket.lake.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_public_access_block" "raw" {
  bucket                  = aws_s3_bucket.raw.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "lake" {
  bucket                  = aws_s3_bucket.lake.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "raw" {
  bucket = aws_s3_bucket.raw.id
  rule {
    id     = "expire-old-versions"
    status = "Enabled"
    noncurrent_version_expiration { noncurrent_days = 30 }
  }
}

output "raw_bucket_name" { value = aws_s3_bucket.raw.bucket }
output "raw_bucket_arn" { value = aws_s3_bucket.raw.arn }
output "lake_bucket_name" { value = aws_s3_bucket.lake.bucket }
output "lake_bucket_arn" { value = aws_s3_bucket.lake.arn }
