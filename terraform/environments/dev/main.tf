# Root Module — Development Environment
#
# Dependency graph:
#   module.kms ──┬──► module.vpc ──┐
#                │                 ├──► module.eks
#                └──► module.iam ──┘

# ─── Data Sources ─────────────────────────────────────────────────────────────

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ─── KMS ──────────────────────────────────────────────────────────────────────

module "kms" {
  source = "../../modules/kms"

  environment    = var.environment
  project        = var.project
  aws_account_id = data.aws_caller_identity.current.account_id
}

# ─── VPC ──────────────────────────────────────────────────────────────────────

module "vpc" {
  source = "../../modules/vpc"

  name                      = var.project
  environment               = var.environment
  cluster_name              = var.cluster_name
  vpc_cidr                  = var.vpc_cidr
  availability_zones        = var.availability_zones
  public_subnet_cidrs       = var.public_subnet_cidrs
  private_eks_subnet_cidrs  = var.private_eks_subnet_cidrs
  private_data_subnet_cidrs = var.private_data_subnet_cidrs
  single_nat_gateway        = var.single_nat_gateway

  depends_on = [module.kms]
}

# ─── IAM (Human Access Roles & GitHub OIDC) ───────────────────────────────────

module "iam" {
  source = "../../modules/iam"

  environment    = var.environment
  project        = var.project
  github_org     = var.github_org
  github_repo    = var.github_repo
  aws_account_id = data.aws_caller_identity.current.account_id
}

# ─── EKS ──────────────────────────────────────────────────────────────────────

module "eks" {
  source = "../../modules/eks"

  cluster_name              = var.cluster_name
  cluster_version           = var.kubernetes_version
  environment               = var.environment
  project                   = var.project
  vpc_id                    = module.vpc.vpc_id
  subnet_ids                = module.vpc.private_eks_subnet_ids
  endpoint_private_access   = var.endpoint_private_access
  endpoint_public_access    = var.endpoint_public_access
  public_access_cidrs       = var.public_access_cidrs
  service_ipv4_cidr         = var.service_ipv4_cidr
  enabled_cluster_log_types = var.enabled_cluster_log_types
  kms_key_arn               = module.kms.eks_key_arn
  node_groups               = var.node_groups

  access_entries = {
    platform_admin = {
      principal_arn     = module.iam.platform_admin_role_arn
      policy_arn        = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
      access_scope_type = "cluster"
      namespaces        = []
    }
    developer = {
      principal_arn     = module.iam.developer_role_arn
      policy_arn        = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"
      access_scope_type = "namespace"
      namespaces        = ["dev"]
    }
    readonly = {
      principal_arn     = module.iam.readonly_role_arn
      policy_arn        = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
      access_scope_type = "cluster"
      namespaces        = []
    }
  }

  depends_on = [module.vpc, module.iam, module.kms]
}

# ─── Security ─────────────────────────────────────────────────────────────────

module "security" {
  source = "../../modules/security"

  environment = var.environment
  project     = var.project
  vpc_id      = module.vpc.vpc_id
  kms_key_arn = module.kms.eks_key_arn

  depends_on = [module.vpc]
}

# ─── ECR ──────────────────────────────────────────────────────────────────────

module "ecr" {
  source = "../../modules/ecr"

  environment  = var.environment
  project      = var.project
  repositories = var.ecr_repositories
  kms_key_arn  = module.kms.ecr_key_arn

  depends_on = [module.kms]
}
