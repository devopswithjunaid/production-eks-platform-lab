# Terraform Design

## State Management

Terraform state will not be stored locally.

State will use:

- Amazon S3 backend
- DynamoDB state locking

Reason:

Multiple engineers can safely work on infrastructure.

State file contains sensitive infrastructure information
and must be protected.

### State Architecture

```
Engineer / CI Pipeline
        │
        ▼
   terraform apply
        │
        ├──► DynamoDB Table (Acquire State Lock)
        │    (Prevents concurrent execution)
        │
        └──► Amazon S3 Bucket (Read / Write terraform.tfstate)
             (Encrypted at rest via KMS + Versioned)
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
