# Root Variables
#
# These variables are declared here and set in terraform.tfvars.
# Modules receive values through their own variable definitions.

# ─── Global ───────────────────────────────────────────────────────────────────

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (dev / staging / production)"
  type        = string
}

variable "project" {
  description = "Project name used for naming and tagging all resources"
  type        = string
  default     = "production-eks-platform-lab"
}

# ─── VPC ──────────────────────────────────────────────────────────────────────

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.20.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones to use"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ)"
  type        = list(string)
  default     = ["10.20.0.0/24", "10.20.1.0/24", "10.20.2.0/24"]
}

variable "private_eks_cidrs" {
  description = "CIDR blocks for private EKS subnets (one per AZ)"
  type        = list(string)
  default     = ["10.20.16.0/20", "10.20.32.0/20", "10.20.48.0/20"]
}

variable "private_data_cidrs" {
  description = "CIDR blocks for private data subnets (one per AZ)"
  type        = list(string)
  default     = ["10.20.64.0/24", "10.20.65.0/24", "10.20.66.0/24"]
}

variable "single_nat_gateway" {
  description = "Use single NAT Gateway (true = dev/cost-optimized, false = prod/HA)"
  type        = bool
  default     = true
}

# ─── EKS ──────────────────────────────────────────────────────────────────────

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version for EKS cluster"
  type        = string
  default     = "1.31"
}

# ─── GitHub (for OIDC IAM Role) ───────────────────────────────────────────────

variable "github_org" {
  description = "GitHub organization name"
  type        = string
  default     = "devopswithjunaid"
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
  default     = "production-eks-platform-lab"
}

# ─── ECR ──────────────────────────────────────────────────────────────────────

variable "ecr_repositories" {
  description = "List of ECR repository names to create"
  type        = list(string)
  default = [
    "frontend",
    "checkout-service",
    "payment-service",
    "cart-service",
    "product-catalog"
  ]
}
