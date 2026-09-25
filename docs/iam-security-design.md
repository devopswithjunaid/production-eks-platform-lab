# IAM Security Design

## Guiding Principles

1. **No long-lived AWS credentials anywhere** — no access keys in secrets, env vars, or code
2. **Every principal has only the permissions it needs** — least privilege always
3. **Human access is federated** — no shared IAM users for engineers
4. **Workloads use temporary credentials** — via EKS Pod Identity
5. **All IAM is version controlled** — Terraform manages every role and policy
6. **Audit trail for everything** — CloudTrail records all IAM and API activity

---

## Human Access

### Design

Engineers never receive static IAM credentials.
All access is federated through IAM Identity Center (SSO).

```
Engineer
    │
    │  Logs in via SSO (Google / corporate IdP)
    ▼
AWS IAM Identity Center
    │
    ├── Assigned Permission Set
    │   ├── PlatformAdmin
    │   ├── Developer
    │   └── ReadOnly
    │
    ▼
Temporary STS credentials
(valid 1–8 hours, auto-expire)
    │
    ├── AWS Console access
    ├── AWS CLI access
    └── kubectl access (via EKS Access Entry)
```

### Permission Sets

#### PlatformAdmin

```
Who:        Senior platform / DevOps engineers
AWS access: Full access to EKS, EC2, VPC, IAM, S3, Route53
K8s access: cluster-admin (full cluster)
Use case:   Platform builds, incident response, upgrades
```

#### Developer

```
Who:        Application developers
AWS access: Read-only ECR, CloudWatch logs
K8s access: edit in dev namespace only
            - Can: view/create pods, deployments, logs, configmaps
            - Cannot: secrets, cluster resources, system namespaces
Use case:   Day-to-day application development and debugging
```

#### ReadOnly

```
Who:        Auditors, stakeholders, security reviewers
AWS access: Read-only across all services
K8s access: view across all namespaces (no write)
Use case:   Compliance, monitoring, review
```

### EKS Access Entry Configuration

```hcl
# Platform Admin Access Entry
resource "aws_eks_access_entry" "platform_admin" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = "arn:aws:iam::ACCOUNT_ID:role/PlatformAdmin"
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "platform_admin" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = "arn:aws:iam::ACCOUNT_ID:role/PlatformAdmin"
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope { type = "cluster" }
}
```

No aws-auth ConfigMap editing. All managed via Terraform and AWS APIs.

---

## CI/CD Access — GitHub Actions

### The Problem with Access Keys

```
WRONG approach:
GitHub Secret: AWS_ACCESS_KEY_ID = AKIA...
GitHub Secret: AWS_SECRET_ACCESS_KEY = xxxx

Problems:
- Long-lived credentials (never expire)
- If leaked → attacker has permanent AWS access
- Rotation is manual and error-prone
- Keys stored in GitHub — attack surface
```

### The Correct Approach — OIDC

```
CORRECT approach:
No AWS credentials stored anywhere.
GitHub proves its identity via OpenID Connect.
AWS issues temporary credentials for each job.
```

### OIDC Authentication Flow

```
GitHub Actions workflow starts
    │
    ▼
GitHub generates OIDC identity token
(signed by GitHub's OIDC provider)
    │
    ▼
Workflow sends token to AWS STS
AssumeRoleWithWebIdentity API call
    │
    ▼
AWS validates token against registered
GitHub OIDC provider in our account
    │
    ▼
AWS checks trust policy conditions:
- Correct GitHub org?       ✓
- Correct repository?       ✓
- Correct branch/ref?       ✓
    │
    ▼
AWS returns temporary credentials
(valid for 15 minutes to 1 hour)
    │
    ▼
GitHub Actions uses credentials
for ECR push only
    │
    ▼
Job ends → credentials automatically expire
```

### IAM Role Trust Policy

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub":
            "repo:devopswithjunaid/production-eks-platform-lab:ref:refs/heads/main"
        }
      }
    }
  ]
}
```

Only our specific repository on the main branch can assume this role.
No other GitHub repo — even in the same org — can use these credentials.

### GitHub Actions IAM Role Permissions

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:PutImage"
      ],
      "Resource": "arn:aws:ecr:REGION:ACCOUNT_ID:repository/production-eks-platform-lab/*"
    }
  ]
}
```

GitHub Actions can ONLY push to our specific ECR repositories.
No EC2, no IAM, no S3, no EKS — nothing else.

---

## Kubernetes Workload Access — EKS Pod Identity

### The Problem with Mounting Credentials

```
WRONG approach:
kubectl create secret generic aws-creds \
  --from-literal=AWS_ACCESS_KEY_ID=AKIA... \
  --from-literal=AWS_SECRET_ACCESS_KEY=xxxx

Problems:
- Static credentials inside Kubernetes secrets
- Kubernetes secrets are base64 encoded (not encrypted by default)
- If etcd is compromised → credentials exposed
- Manual rotation required
- No audit trail of which pod used which credentials
```

### The Correct Approach — EKS Pod Identity

```
CORRECT approach:
Pod → ServiceAccount → EKS Pod Identity → IAM Role → AWS Service

No credentials stored anywhere.
AWS automatically rotates the temporary credentials.
```

### EKS Pod Identity Flow

```
Pod starts on Node
    │
    ▼
Pod is associated with a Kubernetes ServiceAccount
    │
    ▼
EKS Pod Identity Agent (DaemonSet on node)
intercepts AWS SDK calls from the pod
    │
    ▼
Agent calls EKS Pod Identity API
on behalf of the pod's ServiceAccount
    │
    ▼
AWS returns temporary credentials
(rotated every 15 minutes automatically)
    │
    ▼
Pod's AWS SDK uses those temporary credentials
    │
    ▼
Credentials expire after 15 minutes
(refreshed automatically by the Agent)
```

### Example: Payment Service needs Secrets Manager

```
payment-service pod
    │
    ServiceAccount: payment-service-sa
    │
    ▼
EKS Pod Identity Association
(Terraform managed)
    │
    ▼
IAM Role: eks-payment-service-role
    │
    IAM Policy allows ONLY:
    secretsmanager:GetSecretValue
    Resource: arn:aws:secretsmanager:*:*:secret:production/payment/*
    │
    ▼
Payment service reads its secret
Cannot access any other secret
Cannot access S3, EC2, IAM, or any other service
```

### Pod Identity vs IRSA

We use EKS Pod Identity (not the older IRSA approach):

| Feature                | IRSA (Old)         | EKS Pod Identity (New)    |
|------------------------|--------------------|---------------------------|
| Setup complexity       | High               | Simple                    |
| OIDC provider needed   | Yes (manual setup) | Built into EKS            |
| Credential refresh     | Every 24 hours     | Every 15 minutes          |
| Multi-cluster support  | Per-cluster setup  | Reusable across clusters  |
| AWS recommendation     | Legacy             | Current recommended       |

---

## Least Privilege Strategy

### Principle

Every IAM principal — human, CI/CD system, or pod — should have
exactly the permissions needed for its task and nothing more.

### How we enforce it

| Layer              | Mechanism                                    |
|--------------------|----------------------------------------------|
| Human engineers    | IAM Identity Center Permission Sets (scoped) |
| GitHub Actions     | OIDC role with only ECR push permissions     |
| Platform pods      | Pod Identity with service-specific roles     |
| Application pods   | Pod Identity with least-privilege policies   |
| Node IAM role      | AWS managed policies only (no custom admin)  |

### IAM Role Inventory

| Role Name                        | Used By               | Key Permissions                    |
|----------------------------------|-----------------------|------------------------------------|
| eks-cluster-role                 | EKS Control Plane     | AmazonEKSClusterPolicy             |
| eks-node-role                    | Worker Nodes          | EKS worker + ECR pull + VPC CNI   |
| github-actions-ci-role           | GitHub Actions        | ECR push to our repos only         |
| eks-load-balancer-controller-role| LB Controller pod     | ELB + EC2 + IAM (scoped)          |
| eks-external-dns-role            | ExternalDNS pod       | Route53 record management          |
| eks-cert-manager-role            | Cert Manager pod      | Route53 DNS validation only        |
| eks-ebs-csi-driver-role          | EBS CSI Driver pod    | EC2 volume create/attach/delete    |
| eks-cluster-autoscaler-role      | Cluster Autoscaler    | EC2 Auto Scaling describe/update   |
| eks-<service-name>-role          | Per application pod   | Service-specific least privilege   |

### No Wildcard Permissions

We never use:

```json
"Action": "*"
"Resource": "*"
```

Every policy specifies exact actions and exact resource ARNs.

---

## Secret Management Strategy

### Phase 1 — Kubernetes Secrets (Now)

```
Application reads secret from Kubernetes Secret object
Secret is stored in etcd (encrypted at rest via KMS)
Secret is mounted as environment variable or volume
```

We study this first to understand the native mechanism and its limitations:
- Secrets are base64 encoded (not truly encrypted without additional config)
- No audit trail of which pod read which secret
- No automatic rotation
- No dynamic credential generation

### Phase 2 — HashiCorp Vault (Later)

```
Application reads secret from Vault API
Vault stores secrets encrypted
Vault provides dynamic credentials (auto-expiring)
Vault records every secret access in audit log
External Secrets Operator syncs Vault secrets to K8s Secrets
```

We introduce Vault after understanding why it exists — not before.
