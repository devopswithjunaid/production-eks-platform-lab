locals {
  name_prefix = "${var.project}-${var.environment}"

  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  account_root_arn = "arn:aws:iam::${var.aws_account_id}:root"
}

# ─── 1. Human / RBAC IAM Roles for EKS Access Entries ─────────────────────────

data "aws_iam_policy_document" "account_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [local.account_root_arn]
    }
  }
}

resource "aws_iam_role" "platform_admin" {
  name               = "${local.name_prefix}-platform-admin-role"
  assume_role_policy = data.aws_iam_policy_document.account_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-platform-admin-role"
    Role = "PlatformAdmin"
  })
}

resource "aws_iam_role" "developer" {
  name               = "${local.name_prefix}-developer-role"
  assume_role_policy = data.aws_iam_policy_document.account_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-developer-role"
    Role = "Developer"
  })
}

resource "aws_iam_role" "readonly" {
  name               = "${local.name_prefix}-readonly-role"
  assume_role_policy = data.aws_iam_policy_document.account_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-readonly-role"
    Role = "ReadOnly"
  })
}

# ─── 2. GitHub Actions OIDC Role ──────────────────────────────────────────────
#
# NOTE: GitHub's OIDC provider (token.actions.githubusercontent.com) is a
# global per-account resource — only ONE can exist per AWS account.
# We look up the existing one rather than creating it, which would fail with
# EntityAlreadyExists if another project already registered it.

data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

data "aws_iam_policy_document" "github_actions_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org}/${var.github_repo}:*"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = "${local.name_prefix}-github-actions-ci-role"
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-github-actions-ci-role"
  })
}
