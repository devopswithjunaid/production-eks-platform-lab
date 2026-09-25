# Architecture Overview

## Purpose

This document describes the complete high-level architecture of the
Production EKS Platform Lab. It is the entry point for understanding
how every layer connects.

---

## Platform Layers

```
┌─────────────────────────────────────────────────────────────────┐
│                        USER / CLIENT                            │
└───────────────────────────────┬─────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                     DNS LAYER (Route 53)                        │
│   Public DNS resolution → ALB DNS name                         │
└───────────────────────────────┬─────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│             INGRESS LAYER (Application Load Balancer)           │
│   Public Subnets  │  TLS Termination  │  Host/Path Routing      │
└───────────────────────────────┬─────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                  KUBERNETES LAYER (Amazon EKS)                  │
│                                                                 │
│   ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐ │
│   │  Frontend    │  │  Checkout    │  │  Payment Service     │ │
│   │  Service     │→ │  Service     │→ │                      │ │
│   └──────────────┘  └──────────────┘  └──────────────────────┘ │
│                                                                 │
│   Private EKS Subnets │ Multi-AZ │ Managed Node Groups         │
└───────────────────────────────┬─────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                      DATA LAYER                                 │
│   Amazon RDS  │  ElastiCache  │  Private Data Subnets           │
└─────────────────────────────────────────────────────────────────┘
```

---

## AWS Layer

Managed by Terraform:

- VPC (10.20.0.0/16)
- Public Subnets (ALB, NAT)
- Private EKS Subnets (Worker Nodes, Pods)
- Private Data Subnets (RDS, Cache)
- Internet Gateway
- NAT Gateway
- Amazon EKS Control Plane
- Managed Node Groups
- Amazon ECR
- IAM Roles and Policies
- KMS Encryption Keys
- Route 53
- Application Load Balancer (provisioned by AWS Load Balancer Controller)

---

## Kubernetes Layer

Managed by Argo CD (GitOps):

- Application Deployments
- Services
- Ingress Resources
- ConfigMaps
- Secrets
- ServiceAccounts
- RBAC
- NetworkPolicies
- HorizontalPodAutoscalers
- PodDisruptionBudgets

Platform components installed via Helm and managed by Argo CD:

- AWS Load Balancer Controller
- ExternalDNS
- Cert Manager
- Argo CD
- Prometheus Stack
- Grafana
- Loki
- OpenTelemetry Collector
- HashiCorp Vault
- Kyverno
- Falco

---

## CI/CD Layer

Managed by GitHub Actions:

```
Developer pushes code
        │
        ▼
GitHub Actions
        │
        ├── Code linting and tests
        ├── Security scanning (SAST)
        ├── Docker image build
        ├── Container image scanning
        ├── SBOM generation
        ├── Image signing (cosign)
        └── Push to Amazon ECR
```

Authentication to AWS: GitHub OIDC (no long-lived access keys)

---

## GitOps Layer

Managed by Argo CD:

```
ECR (new image tag)
        │
        ▼
GitOps repository updated
(image tag committed)
        │
        ▼
Argo CD detects drift
        │
        ▼
Argo CD reconciles EKS cluster
        │
        ▼
New version deployed
```

Git is the single source of truth for all Kubernetes desired state.

---

## Security Layer

| Area                  | Tool / Method                    |
|-----------------------|----------------------------------|
| AWS access (CI)       | GitHub OIDC + IAM Role           |
| AWS access (humans)   | IAM Identity Center              |
| Pod AWS access        | EKS Pod Identity                 |
| Kubernetes RBAC       | ServiceAccounts + ClusterRoles   |
| Secret management     | Kubernetes Secrets → Vault       |
| Image security        | Trivy scanning + cosign signing  |
| Admission control     | Kyverno policies                 |
| Runtime security      | Falco                            |
| Network isolation     | NetworkPolicies + Security Groups|
| Pod security          | Pod Security Standards           |

---

## Monitoring Layer

| Signal  | Tool                   |
|---------|------------------------|
| Metrics | Prometheus             |
| Dashboards | Grafana             |
| Logs    | Loki                   |
| Traces  | OpenTelemetry + Tempo  |
| Alerts  | Alertmanager           |

---

## Environments

| Environment | Status     | Purpose                          |
|-------------|------------|----------------------------------|
| Development | Phase 1    | Build, learn, experiment         |
| Staging     | Future     | Pre-production validation        |
| Production  | Future     | Live workload                    |
