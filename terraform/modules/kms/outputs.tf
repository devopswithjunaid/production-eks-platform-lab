output "eks_key_arn" {
  description = "KMS key ARN for EKS secrets envelope encryption"
  value       = aws_kms_key.eks.arn
}

output "eks_key_id" {
  description = "KMS key ID for EKS secrets envelope encryption"
  value       = aws_kms_key.eks.key_id
}

output "ecr_key_arn" {
  description = "KMS key ARN for ECR image encryption"
  value       = aws_kms_key.ecr.arn
}
