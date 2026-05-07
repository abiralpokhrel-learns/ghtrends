# Phase 2: ingest Lambda + EventBridge hourly cron.
#
# This module creates everything needed to run the ingest Lambda on a schedule:
#   - IAM role and policy for the Lambda (so it can write to S3 and CloudWatch logs)
#   - The Lambda function itself, pointing at the zip built by lambda/ingest_gh_archive/build.sh
#   - A CloudWatch log group with 14-day retention (so logs don't pile up forever)
#   - An EventBridge rule that fires 5 minutes after every hour
#   - A target connecting the rule to the Lambda
#   - A permission allowing EventBridge to invoke the Lambda
#
# Inputs come from terraform/main.tf:
#   project_name      e.g. "ghtrends"
#   env               e.g. "dev"
#   raw_bucket_name   passed in from module.data_lake (where Parquet is written)
#   raw_bucket_arn    same, but the ARN form (used in IAM policy)

variable "project_name" { type = string }
variable "env" { type = string }
variable "raw_bucket_name" { type = string }
variable "raw_bucket_arn" { type = string }
variable "lake_bucket_name" { type = string } # holds the deployment zip

locals {
  function_name = "${var.project_name}-${var.env}-ingest"
  # Path to the deployment zip, relative to this module file.
  # terraform/modules/lambda_ingest/  -> ../../../lambda/ingest_gh_archive/...
  zip_path = "${path.module}/../../../lambda/ingest_gh_archive/ingest_gh_archive.zip"
}

# ----- IAM role: who the Lambda runs as -----

resource "aws_iam_role" "lambda" {
  name = "${local.function_name}-role"

  # "Trust policy": which AWS service is allowed to assume this role.
  # Lambda needs to assume it to run our code.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Inline policy: what the Lambda is allowed to do once it's running.
resource "aws_iam_role_policy" "lambda" {
  name = "${local.function_name}-policy"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Read and write Parquet files under raw/.
        # NOTE: HeadObject is authorized via s3:GetObject — there is no
        # standalone s3:HeadObject action.
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
        ]
        Resource = "${var.raw_bucket_arn}/*"
      },
      {
        # ListBucket on the bucket ARN is required so HeadObject returns 404
        # (instead of 403) when an object doesn't exist. Our idempotency check
        # in handler.py relies on that distinction.
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = var.raw_bucket_arn
      },
      {
        # Write to CloudWatch Logs.
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.lambda.arn}:*"
      }
    ]
  })
}

# ----- Log group: where Lambda's print statements end up -----

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = 14
}

# ----- Upload the deployment zip to S3 -----
# Direct upload to Lambda is capped at 70 MB. Our zip (pyarrow + boto3 + ...)
# is bigger, so we upload to S3 first and have Lambda pull from there.
# That path supports up to 250 MB.

resource "aws_s3_object" "lambda_zip" {
  bucket = var.lake_bucket_name
  key    = "deploy/lambda/ingest_gh_archive.zip"
  source = local.zip_path
  etag   = filemd5(local.zip_path) # re-uploads when the zip changes
}

# ----- The Lambda function -----

resource "aws_lambda_function" "ingest" {
  function_name = local.function_name
  role          = aws_iam_role.lambda.arn
  handler       = "handler.lambda_handler" # file.function_name inside the zip
  runtime       = "python3.11"
  memory_size   = 512 # MB
  timeout       = 300 # seconds (5 min)

  s3_bucket        = aws_s3_object.lambda_zip.bucket
  s3_key           = aws_s3_object.lambda_zip.key
  source_code_hash = filebase64sha256(local.zip_path) # forces redeploy when zip changes

  environment {
    variables = {
      RAW_BUCKET = var.raw_bucket_name
    }
  }

  # Make sure the policy, log group, and zip upload are ready first.
  depends_on = [
    aws_iam_role_policy.lambda,
    aws_cloudwatch_log_group.lambda,
    aws_s3_object.lambda_zip,
  ]
}

# ----- EventBridge: trigger the Lambda 5 minutes after every hour -----

resource "aws_cloudwatch_event_rule" "hourly" {
  name                = "${local.function_name}-hourly"
  description         = "Trigger ingest Lambda 5 minutes after every hour"
  schedule_expression = "cron(5 * * * ? *)"
  # cron syntax in EventBridge: minute hour day-of-month month day-of-week year
  # Here: minute=5, hour=*, every day, every month, every year
}

resource "aws_cloudwatch_event_target" "lambda" {
  rule      = aws_cloudwatch_event_rule.hourly.name
  target_id = "ingest-lambda"
  arn       = aws_lambda_function.ingest.arn
  # No `input` set — EventBridge sends a default event with no `timestamp` field.
  # The Lambda's _resolve_target_hour() falls back to (now - 2h), which is what we want.
}

# Without this permission, EventBridge can't invoke the Lambda.
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ingest.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.hourly.arn
}

# ----- Outputs (so terraform/main.tf can reference these) -----

output "function_arn" {
  description = "ARN of the ingest Lambda"
  value       = aws_lambda_function.ingest.arn
}

output "function_name" {
  description = "Name of the ingest Lambda"
  value       = aws_lambda_function.ingest.function_name
}
