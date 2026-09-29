# Root Module — Development Environment
#
# Dependency order:
#   module.kms ──► module.vpc
#              ──► module.iam
#   module.vpc ──► module.security ──► module.eks
#   module.iam ──►                    module.eks
#   module.kms ──►                    module.ecr

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ─── KMS ─────────────────────────────────────────────────────────────────────
# Must exist first — KMS key ARNs are consumed by VPC (EBS), EKS (Secrets),
# ECR (images), and Security (CloudTrail) modules.

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

# ─── IAM ──────────────────────────────────────────────────────────────────────
# IAM roles (PlatformAdmin, Developer, ReadOnly, GitHub OIDC) are created
# before EKS so their ARNs can be passed into EKS Access Entries.

module "iam" {
  source = "../../modules/iam"

  environment    = var.environment
  project        = var.project
  github_org     = var.github_org
  github_repo    = var.github_repo
  aws_account_id = data.aws_caller_identity.current.account_id
}

# ─── Security ─────────────────────────────────────────────────────────────────
# VPC endpoints (eks-auth, s3, sts, ecr, cloudwatch), GuardDuty, CloudTrail.
# Must exist after VPC (needs subnet IDs) and before EKS (node pods call eks-auth).

module "security" {
  source = "../../modules/security"

  environment        = var.environment
  project            = var.project
  cluster_name       = var.cluster_name
  vpc_id             = module.vpc.vpc_id
  vpc_cidr           = var.vpc_cidr
  private_subnet_ids = module.vpc.private_eks_subnet_ids
  kms_key_arn        = module.kms.eks_key_arn
  enable_guardduty   = var.enable_guardduty

  depends_on = [module.vpc, module.kms]
}

# ─── EKS ──────────────────────────────────────────────────────────────────────
# Consumes: vpc_id + private_eks_subnet_ids (VPC), kms key (KMS),
#           role ARNs (IAM) for Access Entries.
# Depends on security so VPC endpoints exist before nodes try to use them.

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

  depends_on = [module.vpc, module.iam, module.kms, module.security]
}

# ─── ECR ──────────────────────────────────────────────────────────────────────

module "ecr" {
  source = "../../modules/ecr"

  environment          = var.environment
  project              = var.project
  repositories         = var.ecr_repositories
  kms_key_arn          = module.kms.ecr_key_arn
  lifecycle_keep_count = 30

  depends_on = [module.kms]
}
