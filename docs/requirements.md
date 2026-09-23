# Platform Requirements

## Project

Build and operate a production-style microservices platform on Amazon EKS.

The purpose of this project is to deeply understand AWS, Kubernetes,
Terraform, CI/CD, GitOps, DevSecOps, observability, reliability,
troubleshooting, and platform engineering.

## Application

The platform will initially run a microservices-based e-commerce application.

The workload should contain multiple services communicating with each other
so that Kubernetes networking, service discovery, observability, scaling,
and failure scenarios can be studied.

## Environments

The platform will eventually support:

- Development
- Staging
- Production

Development will be implemented first.

## Infrastructure

Infrastructure should be provisioned using Terraform.

Core infrastructure will include:

- AWS VPC
- Public and private subnets
- Internet Gateway
- NAT Gateway
- Amazon EKS
- Worker nodes
- Amazon ECR
- IAM
- KMS
- Route 53
- Application Load Balancer

## Kubernetes

The project should eventually cover:

- Deployments
- Services
- Ingress
- ConfigMaps
- Secrets
- ServiceAccounts
- RBAC
- NetworkPolicy
- Resource requests and limits
- Health probes
- Horizontal Pod Autoscaling
- Pod Disruption Budgets
- Scheduling
- Storage
- Kubernetes DNS
- Troubleshooting

## CI/CD

CI will use GitHub Actions.

CI responsibilities:

- Code validation
- Testing
- Docker image build
- Security scanning
- Image scanning
- SBOM generation
- Image signing
- Push images to ECR

GitHub Actions should authenticate to AWS using OIDC rather than
long-lived AWS access keys.

## GitOps

Continuous Delivery will use Argo CD.

Git will act as the desired-state source of truth.

Argo CD will deploy and reconcile Kubernetes workloads.

## Secrets

Secrets management will eventually use HashiCorp Vault.

We will first study Kubernetes Secrets before introducing Vault.

## Security

Security should eventually include:

- IAM least privilege
- Kubernetes RBAC
- Pod Security Standards
- NetworkPolicies
- Image vulnerability scanning
- Secret scanning
- SAST
- Signed container images
- Admission policies
- Runtime security

## Observability

The platform will eventually use:

- Prometheus
- Grafana
- Alertmanager
- OpenTelemetry
- Loki
- Tempo

Datadog will be evaluated later.

## Reliability

The platform must eventually support deliberate failure testing.

Examples:

- Pod crashes
- OOMKilled
- Node failure
- DNS failure
- Broken Service
- NetworkPolicy failure
- Failed deployment
- Vault outage
- CPU saturation
- Application latency

Each incident should be documented using:

Symptom → Evidence → Hypothesis → Test → Root Cause → Fix → Prevention

This document becomes our contract for the project.
