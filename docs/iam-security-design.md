# IAM and Security Design

## Purpose

This document defines how AWS identity is managed across the platform.
No long-lived credentials. Least privilege everywhere.

---

## Guiding Principles

1. No long-lived AWS access keys stored anywhere
2. Every principal has only the permissions it needs — nothing more
3. Human access is federated — no direct IAM users for engineers
4. Workloads use temporary credentials via Pod Identity
5. All IAM changes are version controlled in Terraform

---

## Human Access

### Engineer access to AWS

```
Engineer
   │
   ▼
AWS IAM Identity Center (SSO)
   │
   ├── Permission Set: PlatformAdmin
   ├── Permission Set: Developer
   └── Permission Set: ReadOnly
   │
   ▼
Temporary credentials
   │
   ▼
AWS Console / CLI / kubectl
```

Engineers never receive static IAM user credentials.
Session credentials are short-lived (1-8 hours).

### Engineer access to Kubernetes

```
Engineer
   │
   ▼
aws eks update-kubeconfig --name <cluster>
   │
   ▼
IAM identity authenticated via EKS Access Entries
   │
   ▼
Kubernetes RBAC permissions applied
```

| Role           | Kubernetes Permissions              |
|----------------|-------------------------------------|
| PlatformAdmin  | cluster-admin                       |
| Developer      | edit (namespaced)                   |
| ReadOnly       | view (namespaced)                   |

---

## CI/CD Access — GitHub Actions

### Why OIDC?

GitHub Actions must push images to ECR and potentially update
Kubernetes resources. Instead of storing AWS credentials in GitHub Secrets,
we use OpenID Connect (OIDC).

```
GitHub Actions Workflow
        │
        ▼
GitHub OIDC Provider
(GitHub's identity token)
        │
        ▼
AWS IAM OIDC Identity Provider
(Configured in our AWS account)
        │
        ▼
IAM Role: github-actions-ci-role
(Assumed via Web Identity Token)
        │
        ▼
Temporary AWS credentials
(Valid for duration of job only)
        │
        ├── ECR: PushImage, DescribeRepositories
        └── (No EKS permissions — Argo CD deploys)
```

### GitHub OIDC Trust Policy

The IAM role trust policy restricts which GitHub repo and branch
can assume the role:

```json
{
  "Condition": {
    "StringLike": {
      "token.actions.githubusercontent.com:sub":
        "repo:devopswithjunaid/production-eks-platform-lab:ref:refs/heads/main"
    }
  }
}
```

Only the main branch of our specific repository can assume this role.

---

## Kubernetes Workload Access — EKS Pod Identity

### Why Pod Identity?

Application pods often need to call AWS APIs:
- Read Secrets Manager
- Access S3
- Write to SQS

Instead of mounting AWS credentials into pods, we use EKS Pod Identity.

```
Pod starts on Node
   │
   ▼
Pod has ServiceAccount with annotation
   │
   ▼
EKS Pod Identity Agent (DaemonSet on node)
   │
   ▼
AWS IAM Role assumed automatically
   │
   ▼
Pod receives temporary credentials
(rotated automatically)
   │
   ▼
Pod calls AWS APIs with those credentials
```

### Example: Payment Service

```
payment-service Pod
   │
   ServiceAccount: payment-service-sa
   │
   EKS Pod Identity Association
   │
   IAM Role: eks-payment-service-role
   │
   Permissions:
     - secretsmanager:GetSecretValue (payment/* only)
```

The payment service can only read its own secrets. Nothing else.

---

## IAM Role Inventory

| Role Name                     | Used By              | Permissions                          |
|-------------------------------|----------------------|--------------------------------------|
| eks-cluster-role              | EKS Control Plane    | AWS managed: AmazonEKSClusterPolicy  |
| eks-node-role                 | Worker Nodes         | AWS managed: AmazonEKSWorkerNodePolicy, ECR read, VPC CNI |
| github-actions-ci-role        | GitHub Actions       | ECR push, ECR describe               |
| eks-load-balancer-controller  | LB Controller Pod    | ELB, EC2, IAM (limited)             |
| eks-external-dns              | ExternalDNS Pod      | Route53 record management            |
| eks-cert-manager              | Cert Manager Pod     | Route53 DNS validation               |
| eks-ebs-csi-driver            | EBS CSI Driver Pod   | EC2 volume management                |
| eks-cluster-autoscaler        | Cluster Autoscaler   | EC2 Auto Scaling describe/update     |
| eks-<service>-role            | Per app service      | Least-privilege per service          |

---

## Kubernetes RBAC Design

### Namespace isolation

Each application environment runs in its own namespace:

```
production-eks-platform-lab (cluster)
│
├── Namespace: kube-system       (cluster components)
├── Namespace: argocd            (Argo CD)
├── Namespace: monitoring        (Prometheus, Grafana)
├── Namespace: vault             (HashiCorp Vault)
├── Namespace: security          (Falco, Kyverno)
└── Namespace: dev               (application workloads — dev)
```

### RBAC roles per namespace

| ClusterRole / Role | Bound To                | Scope      |
|--------------------|-------------------------|------------|
| cluster-admin      | Platform engineer group | Cluster    |
| edit               | Developer group         | Namespaced |
| view               | Read-only group         | Namespaced |
| argocd-manager     | Argo CD ServiceAccount  | Cluster    |

---

## Secret Management Strategy

| Phase   | Secret Store              | Mechanism                          |
|---------|---------------------------|------------------------------------|
| Phase 1 | Kubernetes Secrets        | Base64 encoded, etcd stored        |
| Phase 2 | HashiCorp Vault + ESO     | Vault secrets synced to K8s Secrets|

Kubernetes Secrets are studied first so we understand the native mechanism
and its limitations before introducing Vault.

Vault will be installed as a Kubernetes workload on the security node group.

---

## Security Scanning

| Stage          | Tool      | Triggered by      |
|----------------|-----------|-------------------|
| SAST           | Semgrep   | GitHub Actions PR |
| Dependency scan| Trivy     | GitHub Actions    |
| Image scan     | Trivy     | GitHub Actions    |
| SBOM           | Syft      | GitHub Actions    |
| Image signing  | cosign    | GitHub Actions    |
| Runtime        | Falco     | Always on in EKS  |
| Admission      | Kyverno   | Always on in EKS  |
