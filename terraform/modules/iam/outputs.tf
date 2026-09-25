output "platform_admin_role_arn" {
  description = "IAM Role ARN for PlatformAdmin EKS access entry"
  value       = aws_iam_role.platform_admin.arn
}

output "developer_role_arn" {
  description = "IAM Role ARN for Developer EKS access entry (dev namespace scoped)"
  value       = aws_iam_role.developer.arn
}

output "readonly_role_arn" {
  description = "IAM Role ARN for ReadOnly EKS access entry"
  value       = aws_iam_role.readonly.arn
}

output "github_actions_role_arn" {
  description = "IAM Role ARN for GitHub Actions OIDC"
  value       = aws_iam_role.github_actions.arn
}
