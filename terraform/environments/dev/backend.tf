# Terraform Backend Configuration
#
# Stores Terraform state in Amazon S3 with DynamoDB locking.
#
# WHY REMOTE STATE?
# -----------------
# Local state (terraform.tfstate) causes problems:
#   - Two engineers applying at the same time = state corruption
#   - State file contains sensitive data (passwords, keys, endpoints)
#   - State is lost if the laptop is lost
#
# S3 backend solves all three:
#   - S3 stores state safely and centrally
#   - DynamoDB provides state locking (only one apply at a time)
#   - S3 versioning allows state rollback if something goes wrong
#
# SETUP REQUIRED BEFORE USE:
# ---------------------------
# 1. Create S3 bucket: production-eks-platform-lab-terraform-state
# 2. Enable S3 versioning on the bucket
# 3. Enable S3 server-side encryption (KMS)
# 4. Create DynamoDB table: production-eks-platform-lab-terraform-locks
#    Partition key: LockID (String)
# 5. Run: terraform init

terraform {
  backend "s3" {
    bucket         = "production-eks-platform-lab-terraform-state"
    key            = "environments/dev/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "production-eks-platform-lab-terraform-locks"
  }
}
