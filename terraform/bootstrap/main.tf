data "aws_caller_identity" "current" {}

locals {
  # Include account ID to guarantee global S3 bucket name uniqueness
  bucket_name = "${var.project}-terraform-state-${data.aws_caller_identity.current.account_id}"
}

# ─── S3 State Bucket ──────────────────────────────────────────────────────────
#
# WHY A SEPARATE BOOTSTRAP LAYER?
# This is the classic Terraform chicken-and-egg problem:
#   - Terraform needs an S3 bucket to store remote state
#   - But Terraform cannot create a bucket that it depends on for state storage
#
# Solution: Run this tiny standalone bootstrap once with local state.
# It creates the S3 bucket, then all real environment configs point at it.
#
# How to run (one time only, before any other terraform apply):
#   cd terraform/bootstrap
#   terraform init
#   terraform apply
#   cd ../environments/dev
#   uncomment backend.tf, update bucket name from output
#   terraform init -migrate-state   (migrates local → S3)

resource "aws_s3_bucket" "terraform_state" {
  bucket = local.bucket_name

  # Prevent accidental deletion of bucket containing all infrastructure state
  lifecycle {
    prevent_destroy = false # set true in production
  }

  tags = {
    Name    = local.bucket_name
    Purpose = "Terraform remote state storage"
  }
}

# Block all public access — state files contain sensitive data
resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket                  = aws_s3_bucket.terraform_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Versioning allows state file rollback if a corruption or bad apply occurs
resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Encrypt state files at rest (AWS-managed key — suitable for bootstrap)
# Production: replace with customer-managed KMS key
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

# Native S3 state locking (Terraform >= 1.10 — no DynamoDB table needed)
# Terraform writes a .tflock object to S3 before apply and removes it after.
# This replaces the deprecated DynamoDB-based locking approach.
resource "aws_s3_bucket_ownership_controls" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Lifecycle: automatically clean up old state versions after 90 days
resource "aws_s3_bucket_lifecycle_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}
