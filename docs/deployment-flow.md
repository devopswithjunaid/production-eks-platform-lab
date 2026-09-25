# Deployment Flow

## Purpose

This document describes the complete CI/CD pipeline from developer
code push to running workload in EKS. Every stage has a clear owner.

---

## Complete Flow

```
Developer
   │
   │  git push / Pull Request
   ▼
GitHub Repository
   │
   ├── Pull Request triggers GitHub Actions
   │
   ▼
─────────────────────────────────────────
STAGE 1: Code Validation          [GitHub Actions]
─────────────────────────────────────────
   │
   ├── Lint (language-specific linter)
   ├── Unit tests
   ├── Integration tests
   └── SAST — Semgrep (Static Analysis)
   │
   ▼ (pass)
─────────────────────────────────────────
STAGE 2: Security Scanning        [GitHub Actions]
─────────────────────────────────────────
   │
   ├── Dependency vulnerability scan (Trivy)
   ├── Secret scanning (Gitleaks)
   └── License compliance check
   │
   ▼ (pass)
─────────────────────────────────────────
STAGE 3: Docker Build             [GitHub Actions]
─────────────────────────────────────────
   │
   ├── Build Docker image
   ├── Tag with: git SHA + branch + timestamp
   └── Multi-stage build (minimal final image)
   │
   ▼
─────────────────────────────────────────
STAGE 4: Container Image Scanning [GitHub Actions]
─────────────────────────────────────────
   │
   ├── Trivy image scan
   ├── CRITICAL vulnerabilities → FAIL pipeline
   └── HIGH vulnerabilities → WARNING (configurable)
   │
   ▼ (pass)
─────────────────────────────────────────
STAGE 5: SBOM + Image Signing     [GitHub Actions]
─────────────────────────────────────────
   │
   ├── SBOM generation (Syft → CycloneDX format)
   ├── SBOM attestation (cosign attest)
   └── Image signing (cosign sign)
   │
   ▼
─────────────────────────────────────────
STAGE 6: Push to ECR              [GitHub Actions]
─────────────────────────────────────────
   │
   ├── Authenticate to AWS via GitHub OIDC
   ├── docker push to Amazon ECR
   └── Image tag recorded
   │
   ▼
─────────────────────────────────────────
STAGE 7: Update GitOps Repository [GitHub Actions]
─────────────────────────────────────────
   │
   ├── Open PR or commit to GitOps repo
   └── Update image tag in Kustomize / Helm values
   │
   ▼
─────────────────────────────────────────
STAGE 8: GitOps Sync              [Argo CD]
─────────────────────────────────────────
   │
   ├── Argo CD detects change in GitOps repo
   ├── Compares desired state (Git) vs actual state (cluster)
   ├── Applies diff to EKS cluster
   └── Monitors rollout health
   │
   ▼
─────────────────────────────────────────
STAGE 9: Deployment to EKS        [Kubernetes]
─────────────────────────────────────────
   │
   ├── Rolling update (zero downtime)
   ├── Health checks verified (readiness probes)
   ├── Old pods terminated after new pods are ready
   └── HPA adjusts replica count based on load
   │
   ▼
Application running in EKS ✓
```

---

## Stage Ownership Summary

| Stage                  | Owner           |
|------------------------|-----------------|
| Code validation        | GitHub Actions  |
| Security scanning      | GitHub Actions  |
| Docker build           | GitHub Actions  |
| Image scanning         | GitHub Actions  |
| SBOM and signing       | GitHub Actions  |
| Push to ECR            | GitHub Actions  |
| Update GitOps repo     | GitHub Actions  |
| Deployment sync        | Argo CD         |
| Runtime orchestration  | Kubernetes      |

---

## Why GitHub Actions does NOT use kubectl apply

GitHub Actions must NOT run `kubectl apply` directly.

Reasons:

1. It creates a second actor modifying cluster state alongside Argo CD
2. It breaks the GitOps single source of truth principle
3. It requires GitHub Actions to have Kubernetes cluster credentials
4. Rollback becomes complex and error-prone

The correct model:

```
GitHub Actions → ECR (image) + GitOps repo (tag)
Argo CD        → EKS cluster (deploy from Git)
```

---

## Environment Promotion

```
Code merged to main
       │
       ▼
Deploy to DEV namespace (automatic)
       │
       │  Manual approval gate
       ▼
Deploy to STAGING namespace
       │
       │  Manual approval gate
       ▼
Deploy to PRODUCTION namespace
```

Git tag or branch strategy controls promotion.
Argo CD ApplicationSets manage environment-specific configurations.

---

## Rollback

### Application rollback

```
Revert commit in GitOps repo
       │
       ▼
Argo CD detects drift
       │
       ▼
Previous image version deployed
```

Rollback is a Git operation — not a kubectl command.

### Kubernetes rollback (emergency)

```
kubectl rollout undo deployment/<name> -n <namespace>
```

Used only in emergencies. Must be followed by a GitOps repo revert
to keep Git and cluster in sync.

---

## AWS Authentication Flow (GitHub OIDC)

```
GitHub Actions job starts
       │
       ▼
actions/configure-aws-credentials action
       │
       ▼
GitHub requests OIDC token from GitHub
       │
       ▼
Token sent to AWS STS AssumeRoleWithWebIdentity
       │
       ▼
AWS validates token against registered OIDC provider
       │
       ▼
Temporary credentials returned (15 min–1 hour)
       │
       ▼
GitHub Actions uses credentials for ECR push
```

No AWS_ACCESS_KEY_ID or AWS_SECRET_ACCESS_KEY stored in GitHub Secrets.
