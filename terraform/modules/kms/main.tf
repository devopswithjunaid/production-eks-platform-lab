locals {
  name_prefix = "${var.project}-${var.environment}"

  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# ─── Customer-Managed KMS Key for EKS Secrets Encryption ──────────────────────

resource "aws_kms_key" "eks" {
  description             = "KMS key for EKS Kubernetes Secrets envelope encryption (${local.name_prefix})"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-eks-secrets-key"
    }
  )
}

resource "aws_kms_alias" "eks" {
  name          = "alias/${local.name_prefix}-eks-secrets"
  target_key_id = aws_kms_key.eks.key_id
}

# ─── Customer-Managed KMS Key for ECR Image Encryption ────────────────────────

resource "aws_kms_key" "ecr" {
  description             = "KMS key for Amazon ECR image encryption (${local.name_prefix})"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-ecr-key"
    }
  )
}

resource "aws_kms_alias" "ecr" {
  name          = "alias/${local.name_prefix}-ecr"
  target_key_id = aws_kms_key.ecr.key_id
}
