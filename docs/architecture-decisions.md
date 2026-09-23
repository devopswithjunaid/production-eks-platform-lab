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

---

## ADR-008 — EKS Network Architecture

Decision:

Use a multi-AZ VPC with separate public, private EKS,
and private data subnets.

EKS worker nodes will run only in private subnets.

Internet-facing AWS load balancers will use public subnets.

Data services will use isolated private data subnets.

Development will initially use one NAT Gateway to reduce cost.

Production architecture will use one NAT Gateway per Availability Zone
for higher availability.

The EKS API endpoint will initially use public and private access,
with public access restricted to trusted administrative networks.

Reason:

This architecture separates ingress, application compute,
and data workloads while providing multiple failure domains,
controlled internet access, and room for future platform growth.
