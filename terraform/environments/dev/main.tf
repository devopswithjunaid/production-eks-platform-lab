# Root Module — Development Environment
#
# This file calls all infrastructure modules in the correct dependency order:
# KMS → VPC → Security → EKS → IAM → ECR

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

# ─── Security ─────────────────────────────────────────────────────────────────

module "security" {
  source = "../../modules/security"

  environment = var.environment
  project     = var.project
  vpc_id      = module.vpc.vpc_id
  kms_key_arn = module.kms.eks_key_arn

  depends_on = [module.vpc]
}

# ─── EKS ──────────────────────────────────────────────────────────────────────

module "eks" {
  source = "../../modules/eks"

  cluster_name           = var.cluster_name
  kubernetes_version     = var.kubernetes_version
  environment            = var.environment
  project                = var.project
  vpc_id                 = module.vpc.vpc_id
  private_subnet_ids     = module.vpc.private_eks_subnet_ids
  node_security_group_id = module.security.eks_node_security_group_id
  kms_key_arn            = module.kms.eks_key_arn

  depends_on = [module.vpc, module.security, module.kms]
}

# ─── IAM ──────────────────────────────────────────────────────────────────────

module "iam" {
  source = "../../modules/iam"

  environment    = var.environment
  project        = var.project
  github_org     = var.github_org
  github_repo    = var.github_repo
  cluster_name   = module.eks.cluster_name
  aws_account_id = data.aws_caller_identity.current.account_id

  depends_on = [module.eks]
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
