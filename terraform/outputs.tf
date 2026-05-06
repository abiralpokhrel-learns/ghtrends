output "raw_bucket_name" {
  description = "S3 bucket holding raw GH Archive Parquet files written by the ingest Lambda"
  value       = module.data_lake.raw_bucket_name
}

output "lake_bucket_name" {
  description = "S3 bucket holding Athena query results, dbt mart output, and the embeddings index"
  value       = module.data_lake.lake_bucket_name
}

# Uncomment as later modules come online.
#
# output "ingest_lambda_arn" {
#   value = module.ingest_lambda.function_arn
# }
