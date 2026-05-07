# Terraform remote state backend.
# This bucket and DynamoDB table must exist before `terraform init` works.
# They are created by bootstrap/create_state_backend.sh in Phase 1.
#
# After running the bootstrap script, replace <TFSTATE_BUCKET> below
# with the actual bucket name printed by the script.

terraform {
  required_version = ">= 1.6"

  backend "s3" {
    bucket         = "ghtrends-tfstate-358982197687" # e.g. ghtrends-tfstate-123456789012
    key            = "ghtrends/dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "tfstate-locks"
    encrypt        = true
    profile        = "ghtrends" # so backend uses the same AWS profile as the providers
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
  }
}
