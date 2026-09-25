# Terraform Infrastructure

This directory contains AWS infrastructure code.

## Architecture

Terraform manages:

- AWS networking
- EKS cluster
- IAM
- ECR
- Encryption
- Security resources

Terraform does not manage application deployments.

Applications are deployed using GitOps with Argo CD.

## Structure

`modules/`

Reusable infrastructure components (`vpc`, `eks`, `iam`, `ecr`, `kms`, `security`).

`environments/`

Environment-specific deployments (`dev`, and later `staging`, `production`).
