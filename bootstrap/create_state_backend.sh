#!/usr/bin/env bash
# One-time: create S3 bucket + DynamoDB table for Terraform remote state.
# This script must run BEFORE the first `terraform init`.
#
# After running, copy the printed bucket name into terraform/backend.tf
# and into your .env as TFSTATE_BUCKET.

set -euo pipefail

# --- Config ---
PROJECT_NAME="${PROJECT_NAME:-ghtrends}"
AWS_REGION="${AWS_REGION:-us-east-1}"
AWS_PROFILE="${AWS_PROFILE:-ghtrends}"

# Bucket name must be globally unique. We append AWS account id.
ACCOUNT_ID=$(aws sts get-caller-identity --profile "$AWS_PROFILE" --query Account --output text)
BUCKET_NAME="${PROJECT_NAME}-tfstate-${ACCOUNT_ID}"
LOCK_TABLE="tfstate-locks"

echo "==> Creating Terraform state backend"
echo "    Region:       $AWS_REGION"
echo "    Profile:      $AWS_PROFILE"
echo "    Bucket name:  $BUCKET_NAME"
echo "    Lock table:   $LOCK_TABLE"
echo ""
read -p "Continue? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

# --- Create S3 bucket ---
echo "==> Creating S3 bucket..."
if [ "$AWS_REGION" == "us-east-1" ]; then
    aws s3api create-bucket \
        --bucket "$BUCKET_NAME" \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE"
else
    aws s3api create-bucket \
        --bucket "$BUCKET_NAME" \
        --region "$AWS_REGION" \
        --create-bucket-configuration LocationConstraint="$AWS_REGION" \
        --profile "$AWS_PROFILE"
fi

# Versioning ON (so corrupt state can be rolled back)
echo "==> Enabling versioning..."
aws s3api put-bucket-versioning \
    --bucket "$BUCKET_NAME" \
    --versioning-configuration Status=Enabled \
    --profile "$AWS_PROFILE"

# Server-side encryption with AWS-managed keys (free)
echo "==> Enabling encryption..."
aws s3api put-bucket-encryption \
    --bucket "$BUCKET_NAME" \
    --server-side-encryption-configuration '{
        "Rules": [{
            "ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}
        }]
    }' \
    --profile "$AWS_PROFILE"

# Block all public access
echo "==> Blocking public access..."
aws s3api put-public-access-block \
    --bucket "$BUCKET_NAME" \
    --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" \
    --profile "$AWS_PROFILE"

# --- Create DynamoDB lock table ---
echo "==> Creating DynamoDB lock table..."
aws dynamodb create-table \
    --table-name "$LOCK_TABLE" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "$AWS_REGION" \
    --profile "$AWS_PROFILE" \
    --tags Key=Project,Value="$PROJECT_NAME" Key=ManagedBy,Value=bootstrap

echo ""
echo "==> Done."
echo ""
echo "Next steps:"
echo "  1. Open terraform/backend.tf"
echo "  2. Replace <TFSTATE_BUCKET> with: $BUCKET_NAME"
echo "  3. Add to your .env file:"
echo "       TFSTATE_BUCKET=$BUCKET_NAME"
echo "  4. Run: make tf-init"
