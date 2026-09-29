data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  name_prefix = "${var.project}-${var.environment}"
  region      = data.aws_region.current.name
  account_id  = data.aws_caller_identity.current.account_id

  common_tags = merge(
    {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    },
    var.tags
  )
}

# ─── 1. Security Group for VPC Interface Endpoints ───────────────────────────
#
# VPC interface endpoints (eks-auth, ecr.api, ecr.dkr, sts) present as ENIs
# inside the private subnets. They need a security group allowing HTTPS (443)
# inbound from the VPC CIDR so that nodes and Pods can reach AWS services
# without traffic leaving the VPC via the NAT Gateway.

resource "aws_security_group" "vpc_endpoints" {
  name        = "${local.name_prefix}-vpc-endpoints-sg"
  description = "Allow HTTPS traffic from VPC to AWS PrivateLink interface endpoints"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTPS from VPC CIDR to VPC interface endpoints"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpc-endpoints-sg"
  })
}

# ─── 2. EKS Auth VPC Interface Endpoint ──────────────────────────────────────
#
# WHY THIS EXISTS:
# When Pods run in private subnets and use EKS Pod Identity to obtain AWS
# credentials, the eks-pod-identity-agent DaemonSet calls the EKS Auth API
# (pods.eks.amazonaws.com / eks-auth service). If there is no VPC endpoint
# for eks-auth, this call must traverse the NAT Gateway and the public internet
# to reach AWS — adding latency and NAT cost, and failing entirely if the NAT
# Gateway is unavailable or if the public EKS endpoint is locked down.
#
# The com.amazonaws.<region>.eks-auth endpoint creates an ENI in each private
# subnet, so the agent's credential calls stay inside the VPC and do NOT
# require NAT Gateway access to the public EKS Auth API.
#
# AWS documentation: https://docs.aws.amazon.com/eks/latest/userguide/pod-id-agent-setup.html

resource "aws_vpc_endpoint" "eks_auth" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${local.region}.eks-auth"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-eks-auth-endpoint"
    Purpose = "EKS Pod Identity Agent credential calls without NAT"
  })
}

# ─── 3. S3 Gateway Endpoint ──────────────────────────────────────────────────
#
# WHY THIS EXISTS:
# Worker nodes pull container images from ECR, which stores image layers in S3.
# Without this endpoint, every image pull generates S3 traffic through the NAT
# Gateway at $0.045/GB. The S3 Gateway endpoint is FREE (no hourly cost, no
# data-processing charge) and routes S3 traffic inside AWS backbone.

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${local.region}.s3"
  vpc_endpoint_type = "Gateway"

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-s3-gateway-endpoint"
    Purpose = "Free S3 routing for ECR image layer pulls without NAT Gateway"
  })
}

# ─── 4. STS VPC Interface Endpoint ───────────────────────────────────────────
#
# STS (Security Token Service) is called when Pod Identity credentials are
# refreshed. Keeping STS calls inside the VPC avoids NAT Gateway dependency
# for credential refresh (which happens every 15 minutes per Pod).

resource "aws_vpc_endpoint" "sts" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${local.region}.sts"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-sts-endpoint"
    Purpose = "STS calls for Pod Identity credential refresh without NAT"
  })
}

# ─── 5. ECR API + DKR VPC Interface Endpoints ────────────────────────────────
#
# ECR requires two endpoints:
# - ecr.api  : The ECR control-plane API (repository metadata, auth token)
# - ecr.dkr  : The Docker registry protocol endpoint (actual image layer pulls)
#
# Without these, every `docker pull` from ECR requires NAT Gateway. At scale
# (rolling deployments with hundreds of Pods pulling layers), NAT data
# processing fees become significant.

resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${local.region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-ecr-api-endpoint"
    Purpose = "ECR API calls without NAT Gateway"
  })
}

resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${local.region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-ecr-dkr-endpoint"
    Purpose = "ECR Docker registry pulls without NAT Gateway"
  })
}

# ─── 6. CloudWatch Logs VPC Interface Endpoint ───────────────────────────────
#
# EKS control-plane logs, container logs (Fluent Bit), and CloudTrail audit
# logs all write to CloudWatch Logs. Without this endpoint, all log shipping
# from the private subnets goes through NAT Gateway.

resource "aws_vpc_endpoint" "cloudwatch_logs" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${local.region}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-cloudwatch-logs-endpoint"
    Purpose = "Log shipping to CloudWatch without NAT Gateway"
  })
}

# ─── 7. GuardDuty ────────────────────────────────────────────────────────────
#
# AWS GuardDuty is a managed threat detection service that continuously
# analyzes VPC Flow Logs, CloudTrail events, and DNS logs for malicious
# activity (port scanning, crypto mining, credential abuse, C2 traffic).
# It costs ~$4/million events — cheap insurance at our cluster scale.

resource "aws_guardduty_detector" "this" {
  count  = var.enable_guardduty ? 1 : 0
  enable = true

  datasources {
    s3_logs {
      enable = true
    }
    kubernetes {
      audit_logs {
        enable = true
      }
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          enable = true
        }
      }
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-guardduty"
  })
}

# ─── 8. CloudTrail ───────────────────────────────────────────────────────────
#
# CloudTrail records every AWS API call (who, what, when, from where) across
# the account. Combined with EKS control-plane audit logs, this gives complete
# visibility into both AWS-layer and Kubernetes-layer actions.
# CloudTrail events are stored in S3 (long-term) AND delivered to CloudWatch
# Logs for real-time querying.

resource "aws_s3_bucket" "cloudtrail" {
  bucket        = "${local.name_prefix}-cloudtrail-${local.account_id}"
  force_destroy = true # allow deletion of non-empty bucket in dev

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-cloudtrail"
  })
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket                  = aws_s3_bucket.cloudtrail.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = true
  }
}

data "aws_iam_policy_document" "cloudtrail_bucket_policy" {
  statement {
    sid    = "AWSCloudTrailAclCheck"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.cloudtrail.arn]
  }

  statement {
    sid    = "AWSCloudTrailWrite"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${local.account_id}/*"]
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  policy = data.aws_iam_policy_document.cloudtrail_bucket_policy.json

  depends_on = [aws_s3_bucket_public_access_block.cloudtrail]
}

resource "aws_cloudwatch_log_group" "cloudtrail" {
  name              = "/aws/cloudtrail/${local.name_prefix}"
  retention_in_days = var.cloudtrail_retention_days

  tags = merge(local.common_tags, {
    Name = "/aws/cloudtrail/${local.name_prefix}"
  })
}

resource "aws_iam_role" "cloudtrail_cloudwatch" {
  name = "${local.name_prefix}-cloudtrail-cw-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "cloudtrail.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "cloudtrail_cloudwatch" {
  name = "${local.name_prefix}-cloudtrail-cw-policy"
  role = aws_iam_role.cloudtrail_cloudwatch.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
    }]
  })
}

resource "aws_cloudtrail" "this" {
  name                          = "${local.name_prefix}-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  include_global_service_events = true
  is_multi_region_trail         = false
  enable_log_file_validation    = true
  kms_key_id                    = var.kms_key_arn

  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.cloudtrail_cloudwatch.arn

  event_selector {
    read_write_type           = "All"
    include_management_events = true
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-trail"
  })

  depends_on = [
    aws_s3_bucket_policy.cloudtrail,
    aws_cloudwatch_log_group.cloudtrail
  ]
}
