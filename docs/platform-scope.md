# Platform Ownership

## Terraform owns

AWS infrastructure:

- VPC
- Subnets
- Route tables
- NAT
- EKS
- IAM
- ECR
- KMS
- AWS networking
- Required AWS integrations

## GitHub Actions owns

Application CI:

- Tests
- Linting
- Security checks
- Docker builds
- Container scanning
- SBOM
- Image signing
- ECR publishing

GitHub Actions should NOT directly manage normal application deployments
using kubectl apply.

## Argo CD owns

Kubernetes desired state:

- Application deployments
- Services
- Ingress
- Configuration
- GitOps reconciliation
- Environment promotion
- Rollbacks
- Platform Kubernetes components

## Vault owns

Application and platform secrets that require centralized or dynamic
secret management.

## Kubernetes owns

Application runtime orchestration:

- Scheduling
- Health checks
- Restart behavior
- Service discovery
- Scaling
- Workload isolation

This may look simple, but it teaches a very important platform-engineering concept:

Every system needs a clear owner.

Otherwise Terraform, Helm, Argo and CI can start fighting over the same resources.
