# ECR Module

## Purpose

This module creates Amazon ECR repositories for container images.

## Resources Created

- ECR repositories per application service
- Repository encryption (KMS)
- Image scanning configuration (on push)
- Lifecycle policies (remove old images automatically)
- Repository policies (who can push / pull)

## Inputs

| Variable              | Description                                    |
|-----------------------|------------------------------------------------|
| `environment`         | Environment name                               |
| `project`             | Project name for tagging                       |
| `repositories`        | List of repository names to create             |
| `kms_key_arn`         | KMS key ARN for repository encryption          |
| `image_tag_mutability`| MUTABLE or IMMUTABLE image tags                |
| `scan_on_push`        | Enable vulnerability scanning on image push    |
| `lifecycle_keep_count`| Number of tagged images to keep per repo       |

## Outputs

| Output              | Description                                   |
|---------------------|-----------------------------------------------|
| `repository_urls`   | Map of repository name → repository URL       |
| `repository_arns`   | Map of repository name → repository ARN       |

## Lifecycle Policy

Automatically removes:
- Untagged images older than 1 day
- Tagged images when count exceeds `lifecycle_keep_count` (default: 30)

This prevents ECR storage costs from growing unbounded.

## Usage

```hcl
module "ecr" {
  source = "../../modules/ecr"

  environment  = "dev"
  project      = "production-eks-platform-lab"
  kms_key_arn  = module.kms.ecr_key_arn
  repositories = [
    "frontend",
    "checkout-service",
    "payment-service",
    "cart-service",
    "product-catalog"
  ]
}
```
