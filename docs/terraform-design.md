# Terraform Design

## State Management

Terraform state will not be stored locally.

State will use:

- Amazon S3 backend
- S3-native state locking (`use_lockfile = true`)

> **Note:** Terraform 1.10+ supports native S3 state locking using `.tflock` objects directly in S3 (`use_lockfile = true`), and HashiCorp has deprecated `dynamodb_table` locking. We use `use_lockfile = true` so no separate DynamoDB table is required.

Reason:

Multiple engineers can safely work on infrastructure without concurrent state corruption.

State file contains sensitive infrastructure information and must be encrypted at rest and versioned in S3.

### State Architecture

```
Engineer / CI Pipeline
        │
        ▼
   terraform apply
        │
        ├──► Amazon S3 (.tflock file via use_lockfile = true)
        │    (Acquires state lock — prevents concurrent execution)
        │
        └──► Amazon S3 Bucket (Read / Write terraform.tfstate)
             (Encrypted at rest via KMS + S3 Versioning enabled)
```

---

## Module Strategy

Infrastructure is separated into reusable modules:

- **VPC** (`modules/vpc`): Subnets, NAT, IGW, Route Tables, EKS subnet tags
- **EKS** (`modules/eks`): Control plane, Managed Node Groups, Access Entries, Addons
- **IAM** (`modules/iam`): GitHub OIDC, EKS Pod Identity Roles, Human Admin/Dev roles
- **ECR** (`modules/ecr`): Container registries, KMS encryption, image scanning, lifecycle policies
- **KMS** (`modules/kms`): Customer-managed encryption keys for EKS, EBS, ECR, and Secrets
- **Security** (`modules/security`): Security groups, CloudTrail, GuardDuty, VPC Flow Logs

### Why Modules?

1. **Reusability**: The exact same VPC and EKS modules are used across `dev`, `staging`, and `production`.
2. **Isolation of Concerns**: Changes to ECR lifecycle policies do not risk touching VPC routing tables.
3. **Readability & Maintainability**: Instead of a 3,000-line `main.tf`, each module has a clear `variables.tf` (inputs) and `outputs.tf` (outputs).

---

## Environment Strategy

Separate environments:

- `dev`
- `staging`
- `production`

Each environment has **independent state** (`environments/dev/terraform.tfstate`, `environments/production/terraform.tfstate`).

### Why Separate State per Environment?

- Blast radius isolation: A mistake in `dev` cannot corrupt or destroy `production` state.
- Different cost/HA profiles: `dev` uses `single_nat_gateway = true` and smaller instance types (`t3.medium` / `t3.large`), while `production` uses 1 NAT Gateway per AZ and larger/mixed instances.

---

## Dependency Order

```
KMS ──► VPC ──► Security ──► EKS ──► IAM
 │
 └────► ECR
```
