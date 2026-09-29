output "state_bucket_name" {
  description = "S3 bucket name for Terraform remote state — use this in environments/dev/backend.tf"
  value       = aws_s3_bucket.terraform_state.id
}

output "state_bucket_arn" {
  description = "S3 bucket ARN for Terraform remote state"
  value       = aws_s3_bucket.terraform_state.arn
}

output "state_bucket_region" {
  description = "AWS region of the Terraform state bucket"
  value       = aws_s3_bucket.terraform_state.region
}
