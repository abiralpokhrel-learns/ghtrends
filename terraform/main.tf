# Top-level module composition.
# Each phase enables a new module here. Start with everything commented out
# except Phase 1.

# --- Phase 1: data lake buckets ---
module "data_lake" {
  source       = "./modules/s3_data_lake"
  project_name = var.project_name
  env          = var.env
}

# --- Phase 2: ingest lambda + EventBridge cron ---
module "ingest_lambda" {
  source           = "./modules/lambda_ingest"
  project_name     = var.project_name
  env              = var.env
  raw_bucket_name  = module.data_lake.raw_bucket_name
  raw_bucket_arn   = module.data_lake.raw_bucket_arn
  lake_bucket_name = module.data_lake.lake_bucket_name
}

# --- Phase 3: glue catalog + crawler over the partitioned Parquet ---
module "glue_catalog" {
  source          = "./modules/glue_catalog"
  project_name    = var.project_name
  env             = var.env
  raw_bucket_name = module.data_lake.raw_bucket_name
  raw_bucket_arn  = module.data_lake.raw_bucket_arn
}

# --- Phase 6: read-only IAM user for Streamlit Community Cloud ---
# module "streamlit_reader" {
#   source           = "./modules/streamlit_reader"
#   project_name     = var.project_name
#   env              = var.env
#   data_bucket_arns = [module.data_lake.raw_bucket_arn, module.data_lake.lake_bucket_arn]
# }

# Notes on what's intentionally NOT here (see NEXT.md):
#   - No EC2 worker. Streamlit runs on Streamlit Community Cloud.
#   - No RDS or Docker Postgres. Embeddings live in S3 as numpy + parquet.
#   - No Step Functions. EventBridge -> Lambda direct.
#   - No Iceberg. Plain Parquet partitioned by date.
