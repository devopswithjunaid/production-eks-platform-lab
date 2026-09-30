# Terraform Backend Configuration
#
# Stores Terraform state in Amazon S3 with S3-native state locking.
#
# WHY S3-NATIVE LOCKING (use_lockfile = true)?
# --------------------------------------------
# Modern Terraform supports native S3 state locking using a .tflock file
# directly inside the S3 bucket (via conditional writes), deprecating
# the legacy DynamoDB lock table approach.

terraform {
  backend "s3" {
    bucket       = "production-eks-platform-lab-terraform-state-526247032255"
    key          = "environments/dev/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
