# IAM Module

## Purpose

This module creates all IAM roles and policies for the platform.

## Resources Created

- GitHub Actions OIDC Provider and IAM Role
- EKS Pod Identity roles per service
- Platform admin access roles
- Developer access roles
- IAM policies (least privilege per role)

## Inputs

| Variable                  | Description                                     |
|---------------------------|-------------------------------------------------|
| `environment`             | Environment name                                |
| `project`                 | Project name for tagging                        |
| `github_org`              | GitHub organization name                        |
| `github_repo`             | GitHub repository name                          |
| `ecr_repository_arns`     | List of ECR ARNs GitHub Actions can push to     |
| `cluster_name`            | EKS cluster name (for Pod Identity associations)|
| `aws_account_id`          | AWS account ID                                  |

## Outputs

| Output                         | Description                              |
|--------------------------------|------------------------------------------|
| `github_actions_role_arn`      | IAM Role ARN for GitHub Actions (OIDC)   |
| `eks_admin_role_arn`           | IAM Role ARN for EKS cluster admins      |
| `pod_identity_role_arns`       | Map of service → IAM Role ARN            |

## Usage

```hcl
module "iam" {
  source = "../../modules/iam"

  environment    = "dev"
  project        = "production-eks-platform-lab"
  github_org     = "devopswithjunaid"
  github_repo    = "production-eks-platform-lab"
  aws_account_id = data.aws_caller_identity.current.account_id
}
```
