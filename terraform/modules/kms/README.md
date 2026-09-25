# KMS Module

## Purpose

This module creates AWS KMS encryption keys for the platform.

## Resources Created

- KMS key for EKS secrets encryption (etcd encryption at rest)
- KMS key for EBS volume encryption (node and PVC volumes)
- KMS key for ECR image encryption
- KMS key for Secrets Manager
- Key aliases for human-readable identification
- Key policies (least privilege access)

## Inputs

| Variable        | Description                                     |
|-----------------|-------------------------------------------------|
| `environment`   | Environment name                                |
| `project`       | Project name for tagging                        |
| `aws_account_id`| AWS account ID for key policies                 |

## Outputs

| Output              | Description                            |
|---------------------|----------------------------------------|
| `eks_key_arn`       | KMS key ARN for EKS secrets encryption |
| `ebs_key_arn`       | KMS key ARN for EBS encryption         |
| `ecr_key_arn`       | KMS key ARN for ECR encryption         |
| `secrets_key_arn`   | KMS key ARN for Secrets Manager        |

## Why KMS?

Without KMS encryption:
- EKS etcd stores Kubernetes Secrets in plaintext
- EBS volumes store pod data unencrypted
- ECR images are unencrypted at rest

With KMS:
- All data at rest is encrypted with customer-managed keys
- Key rotation is controlled by us
- Key access is audited in CloudTrail
- Required for many compliance frameworks (SOC2, PCI, HIPAA)

## Usage

```hcl
module "kms" {
  source = "../../modules/kms"

  environment    = "dev"
  project        = "production-eks-platform-lab"
  aws_account_id = data.aws_caller_identity.current.account_id
}
```
