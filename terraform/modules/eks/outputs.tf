output "cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.this.name
}

output "cluster_arn" {
  description = "EKS cluster ARN"
  value       = aws_eks_cluster.this.arn
}

output "cluster_endpoint" {
  description = "EKS API server endpoint URL"
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_ca_certificate" {
  description = "Base64-encoded certificate authority data for the EKS cluster"
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS control plane ENIs"
  value       = aws_security_group.cluster.id
}

output "node_security_group_id" {
  description = "Security group ID attached to the EKS worker nodes"
  value       = aws_security_group.node.id
}

output "cluster_iam_role_arn" {
  description = "IAM Role ARN used by the EKS control plane"
  value       = aws_iam_role.cluster.arn
}

output "node_iam_role_arn" {
  description = "IAM Role ARN used by the EKS worker nodes"
  value       = aws_iam_role.node.arn
}

output "node_group_names" {
  description = "Map of Managed Node Group names"
  value       = { for k, v in aws_eks_node_group.this : k => v.node_group_name }
}
