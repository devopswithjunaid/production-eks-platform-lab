# Environment: Development
# Values for all declared variables
#
# This file is committed to Git.
# Do NOT put AWS credentials or secrets here.

# ─── Global ───────────────────────────────────────────────────────────────────
environment = "dev"
aws_region  = "us-east-1"
project     = "production-eks-platform-lab"

# ─── VPC ──────────────────────────────────────────────────────────────────────
vpc_cidr           = "10.20.0.0/16"
availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]

public_subnet_cidrs = [
  "10.20.0.0/24",
  "10.20.1.0/24",
  "10.20.2.0/24"
]

private_eks_subnet_cidrs = [
  "10.20.16.0/20",
  "10.20.32.0/20",
  "10.20.48.0/20"
]

private_data_subnet_cidrs = [
  "10.20.64.0/24",
  "10.20.65.0/24",
  "10.20.66.0/24"
]

# Development: single NAT Gateway (cost optimized)
# Production:  set to false → one NAT Gateway per AZ
single_nat_gateway = true

# ─── EKS ──────────────────────────────────────────────────────────────────────
cluster_name       = "production-eks-dev"
kubernetes_version = "1.31"

# ─── GitHub OIDC ──────────────────────────────────────────────────────────────
github_org  = "devopswithjunaid"
github_repo = "production-eks-platform-lab"

# ─── ECR ──────────────────────────────────────────────────────────────────────
ecr_repositories = [
  "frontend",
  "checkout-service",
  "payment-service",
  "cart-service",
  "product-catalog"
]
