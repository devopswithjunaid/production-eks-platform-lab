# Outputs — Development Environment

# ─── VPC ──────────────────────────────────────────────────────────────────────

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = module.vpc.vpc_cidr
}

output "public_subnet_ids" {
  description = "Public subnet IDs (for ALB and NAT Gateway)"
  value       = module.vpc.public_subnet_ids
}

output "private_eks_subnet_ids" {
  description = "Private EKS subnet IDs (for worker nodes)"
  value       = module.vpc.private_eks_subnet_ids
}

output "private_data_subnet_ids" {
  description = "Private data subnet IDs (for RDS, ElastiCache)"
  value       = module.vpc.private_data_subnet_ids
}

output "nat_gateway_ids" {
  description = "NAT Gateway IDs"
  value       = module.vpc.nat_gateway_ids
}

output "availability_zones" {
  description = "Configured Availability Zones"
  value       = module.vpc.availability_zones
}

# ─── EKS ──────────────────────────────────────────────────────────────────────

output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = module.eks.cluster_endpoint
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "EKS cluster CA certificate"
  value       = module.eks.cluster_ca_certificate
  sensitive   = true
}

# ─── ECR ──────────────────────────────────────────────────────────────────────

output "ecr_repository_urls" {
  description = "ECR repository URLs for all services"
  value       = module.ecr.repository_urls
}

# ─── IAM ──────────────────────────────────────────────────────────────────────

output "github_actions_role_arn" {
  description = "IAM Role ARN for GitHub Actions OIDC authentication"
  value       = module.iam.github_actions_role_arn
}

# ─── KMS ──────────────────────────────────────────────────────────────────────

output "eks_kms_key_arn" {
  description = "KMS key ARN used for EKS secrets encryption"
  value       = module.kms.eks_key_arn
  sensitive   = true
}
