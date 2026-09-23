# Architecture Decisions

## ADR-001 — Amazon EKS

Decision:
Use Amazon EKS rather than self-managed Kubernetes.

Reason:
The project focuses on operating workloads and platform components while
AWS manages the Kubernetes control plane.

---

## ADR-002 — Terraform

Decision:
Provision AWS infrastructure using Terraform.

Reason:
Infrastructure should be repeatable, reviewable and version controlled.

---

## ADR-003 — GitHub Actions

Decision:
Use GitHub Actions for Continuous Integration.

Reason:
CI should validate, test, scan and package application artifacts.

---

## ADR-004 — Argo CD

Decision:
Use Argo CD for Continuous Delivery.

Reason:
Deployments should follow GitOps principles. Git should represent the
desired Kubernetes state.

---

## ADR-005 — AWS Authentication

Decision:
Use GitHub OIDC with AWS IAM.

Reason:
Avoid storing long-lived AWS access keys inside GitHub Secrets.

---

## ADR-006 — Secrets Management

Decision:
Introduce HashiCorp Vault after understanding native Kubernetes Secrets.

Reason:
We want to understand both the Kubernetes-native mechanism and why
organizations introduce an external secret-management platform.

---

## ADR-007 — Observability

Decision:
Start with Prometheus, Grafana and OpenTelemetry before introducing Datadog.

Reason:
Understand the underlying observability concepts before relying on a
commercial observability platform.
