output "vpc_endpoints_security_group_id" {
  description = "Security group ID attached to all VPC interface endpoints"
  value       = aws_security_group.vpc_endpoints.id
}

output "eks_auth_endpoint_id" {
  description = "VPC endpoint ID for the EKS Auth API (required for Pod Identity in private subnets)"
  value       = aws_vpc_endpoint.eks_auth.id
}

output "s3_endpoint_id" {
  description = "VPC Gateway endpoint ID for S3"
  value       = aws_vpc_endpoint.s3.id
}

output "cloudtrail_arn" {
  description = "ARN of the CloudTrail trail"
  value       = aws_cloudtrail.this.arn
}

output "cloudtrail_bucket_name" {
  description = "S3 bucket name storing CloudTrail logs"
  value       = aws_s3_bucket.cloudtrail.id
}

output "guardduty_detector_id" {
  description = "GuardDuty detector ID (empty string if GuardDuty is disabled)"
  value       = var.enable_guardduty ? aws_guardduty_detector.this[0].id : ""
}
