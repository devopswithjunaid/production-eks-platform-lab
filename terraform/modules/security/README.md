# Security Module

## Purpose

This module creates the AWS security baseline for the platform.

## Resources Created

- Security Groups (ALB, EKS nodes, RDS, ElastiCache)
- CloudTrail trail (all API activity logging)
- GuardDuty detector (threat detection)
- AWS Config rules (compliance checking)
- IAM Password Policy
- VPC Flow Logs

## Inputs

| Variable        | Description                                  |
|-----------------|----------------------------------------------|
| `environment`   | Environment name                             |
| `project`       | Project name for tagging                     |
| `vpc_id`        | VPC ID for security group creation           |
| `kms_key_arn`   | KMS key for CloudTrail log encryption        |
| `log_bucket`    | S3 bucket for CloudTrail and flow logs       |

## Outputs

| Output                    | Description                              |
|---------------------------|------------------------------------------|
| `alb_security_group_id`   | Security group ID for ALB                |
| `eks_node_security_group_id`| Security group ID for EKS nodes       |
| `rds_security_group_id`   | Security group ID for RDS               |
| `cache_security_group_id` | Security group ID for ElastiCache       |

## Security Groups Design

```
ALB Security Group
  Inbound:  0.0.0.0/0 → 443, 80
  Outbound: EKS node SG → 80, 443, 8080

EKS Node Security Group
  Inbound:  ALB SG → application ports
  Inbound:  Node → Node (cluster networking)
  Outbound: All (internet via NAT, AWS APIs)

RDS Security Group
  Inbound:  EKS node SG → 5432 (PostgreSQL)
  Outbound: None required

ElastiCache Security Group
  Inbound:  EKS node SG → 6379 (Redis)
  Outbound: None required
```

## Usage

```hcl
module "security" {
  source = "../../modules/security"

  environment  = "dev"
  project      = "production-eks-platform-lab"
  vpc_id       = module.vpc.vpc_id
  kms_key_arn  = module.kms.eks_key_arn
}
```
