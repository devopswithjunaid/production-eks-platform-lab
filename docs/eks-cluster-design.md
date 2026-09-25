# Amazon EKS Cluster Design

## Overview

Our platform uses the following architecture:

```
Amazon EKS
+
Managed Kubernetes Control Plane
+
Managed Node Groups
+
Terraform Provisioning
+
GitOps Deployment (Argo CD)
```

### Architecture Layers

```
┌──────────────────────────────────────────┐
│      AWS Managed Control Plane           │
│                                          │
│  kube-apiserver  │  etcd  │  scheduler   │
│  controller-manager                      │
└─────────────────────┬────────────────────┘
                      │
                      │ (Kubernetes API)
                      │
┌─────────────────────▼────────────────────┐
│           Worker Nodes (EC2)             │
│                                          │
│  System Node Group                       │
│  Application Node Group                  │
│  Monitoring Node Group                   │
└─────────────────────┬────────────────────┘
                      │
┌─────────────────────▼────────────────────┐
│           Application Pods               │
│                                          │
│  Frontend │ Checkout │ Payment │ Cart    │
└──────────────────────────────────────────┘
```

### Responsibility Split

| Responsibility                  | Owner        |
|---------------------------------|--------------|
| Kubernetes API Server           | AWS          |
| etcd database                   | AWS          |
| Control plane high availability | AWS          |
| Control plane patching          | AWS          |
| Worker nodes                    | Us (Terraform)|
| Kubernetes objects              | Us (Argo CD) |
| Application deployments         | Us (Argo CD) |
| Security policies               | Us           |
| Addon management                | Us           |
| Node scaling                    | Us (Karpenter/CA)|

---

## Control Plane Design

### Decision

Use AWS managed Kubernetes control plane via Amazon EKS.

### Reason

We want to focus on operating workloads, building platform capabilities,
and learning Kubernetes — not managing Kubernetes masters, etcd backups,
or control plane HA ourselves.

### What the Control Plane includes

| Component           | Role                                              |
|---------------------|---------------------------------------------------|
| kube-apiserver      | Central API gateway — all kubectl commands hit this|
| etcd                | Distributed key-value store — cluster state        |
| kube-scheduler      | Decides which node a pod runs on                  |
| controller-manager  | Reconciles desired state vs actual state          |

### Senior Design Questions

**Q: Why don't we create EC2 instances for Kubernetes masters?**

AWS already manages the Kubernetes control plane, including:
- High availability across multiple AZs
- Automatic etcd backups and recovery
- Control plane version upgrades
- Health monitoring and auto-replacement

Self-managing masters requires deep Kubernetes internals expertise
and significant operational overhead. EKS removes this burden
so we can focus on platform and application layer work.

**Q: If all worker nodes fail, does the Kubernetes control plane fail?**

No. The control plane and worker nodes are completely separate
failure domains. If every worker node terminates:

- The API server stays available
- etcd keeps storing cluster state
- Existing pod specs remain in etcd
- When nodes come back, pods are rescheduled

The reverse is also true — a control plane issue does not kill
running pods on worker nodes. Pods keep running until the node
itself fails.

---

## Kubernetes Version Strategy

### Decision

Use the latest stable EKS-supported Kubernetes version at provisioning time.
Define the version as a Terraform variable so upgrades are a one-line change.

```hcl
variable "kubernetes_version" {
  description = "EKS Kubernetes version"
  type        = string
  default     = "1.31"
}
```

### Supported versions

AWS supports three Kubernetes minor versions at a time.
Each version is supported for approximately 14 months after release.

### Upgrade Strategy

```
New Kubernetes version released by AWS
              │
              ▼
Upgrade Dev cluster first
              │
    ┌─────────▼──────────┐
    │  Test all workloads │
    │  Test all addons    │
    │  Test all policies  │
    └─────────┬──────────┘
              │
              ▼
Upgrade Staging cluster
              │
    ┌─────────▼──────────┐
    │  Regression testing │
    │  Load testing       │
    └─────────┬──────────┘
              │
              ▼
Upgrade Production cluster
```

**Rule: Never upgrade Production first.**

### Upgrade Risks

| Risk                      | Mitigation                                    |
|---------------------------|-----------------------------------------------|
| API deprecations          | Review Kubernetes changelog before upgrade    |
| Addon incompatibility     | Test addon versions against new K8s version   |
| Breaking workload changes | Run workloads in dev with new version first   |
| Node group rolling update | Managed node groups handle rolling replacement|

### What happens if a Kubernetes version is deprecated?

AWS sends advance notice (typically 60 days). After the deprecation date:
- AWS will auto-upgrade the cluster to the next supported version
- This can break workloads using deprecated APIs
- This is why we follow a proactive upgrade cadence

---

## Network Configuration

| Setting              | Value                                    |
|----------------------|------------------------------------------|
| VPC                  | 10.20.0.0/16                             |
| CNI Plugin           | AWS VPC CNI                              |
| Service CIDR         | 172.20.0.0/16                            |
| Pod networking       | VPC-native (real VPC IPs per pod)        |
| DNS provider         | CoreDNS                                  |
| Proxy mode           | kube-proxy (iptables)                    |
| Worker node subnets  | Private EKS Subnets only                 |

### AWS VPC CNI Behaviour

Every Pod gets a real VPC IP address from the EKS private subnet.
There is no overlay network. Pod-to-pod traffic is native VPC routing.

This means:
- Pods consume real VPC IPs
- EKS subnets must be large (/20 — 4096 IPs per AZ)
- Pod IPs are directly routable within the VPC

---

## API Endpoint Configuration

### Initial Configuration

```
EKS API Endpoint
├── Public Access:   ENABLED
│   └── Restricted to: trusted admin CIDRs only
└── Private Access:  ENABLED
    └── Node-to-control-plane traffic stays inside VPC
```

### Why Public + Private?

| Concern                        | Solution                              |
|--------------------------------|---------------------------------------|
| Node traffic leaving the VPC   | Private endpoint keeps it inside VPC  |
| Admin access from laptop       | Public endpoint allows external access|
| Security of public endpoint    | Restricted to specific CIDR ranges    |

### Future State (Private-Only)

```
EKS API Endpoint
├── Public Access:   DISABLED
└── Private Access:  ENABLED
    └── Access via: VPN / Bastion / AWS SSM
```

Private-only eliminates all public API exposure.
Requires an administrative access path into the VPC.
We will implement this after VPN or SSM access is configured.

---

## Authentication Design

### Decision

We will NOT use `aws-auth` ConfigMap as our primary authentication method.

We WILL use **EKS Access Entries** — the modern AWS-native approach.

### Why not aws-auth ConfigMap?

- ConfigMap is easy to misconfigure (YAML errors lock everyone out)
- No audit trail of who changed it
- Not managed by AWS APIs — just a Kubernetes object
- Error-prone manual editing

### Why EKS Access Entries?

- AWS API-managed (Terraform can manage it)
- Full CloudTrail audit trail
- No risk of locking yourself out via YAML mistakes
- Integrates cleanly with IAM Identity Center

### Authentication Flow

```
Engineer
    │
    ▼
AWS IAM Identity (IAM Identity Center / IAM User)
    │
    ▼
EKS Access Entry
(maps IAM ARN → Kubernetes access policy)
    │
    ▼
Kubernetes RBAC
    │
    ▼
Namespace-level Permissions
```

### Role Design

#### Platform Admin

```
Who:    Senior platform engineers
Access: Full cluster management
Policy: AmazonEKSClusterAdminPolicy
Scope:  Cluster-wide
```

#### Developer

```
Who:    Application developers
Access: Application namespace only
Policy: AmazonEKSEditPolicy
Scope:  dev namespace
        Can: view pods, logs, deployments
        Cannot: cluster-admin, modify system namespaces
```

#### CI/CD Role (GitHub Actions)

```
Who:    GitHub Actions workflows
Access: ECR push + limited EKS access
Auth:   GitHub OIDC → IAM Role (no static keys)
```

---

## Logging Configuration

### Decision

Enable all five EKS control plane log types.

| Log Type         | What it captures                              |
|------------------|-----------------------------------------------|
| api              | All Kubernetes API requests                   |
| audit            | Who did what to which resource and when       |
| authenticator    | IAM authentication events (who logged in)     |
| controllerManager| Reconciliation decisions, deployment events   |
| scheduler        | Pod scheduling decisions and failures         |

### Log Destination

All control plane logs → Amazon CloudWatch Logs

Log group: `/aws/eks/<cluster-name>/cluster`

Retention: 90 days (production), 30 days (dev)

### Why enable all log types?

**Example scenario:**

> "Someone deleted the payment-service deployment in production. Who did it?"

Without audit logs: You cannot answer this.

With audit logs:
```
CloudWatch Logs Insights query:
{ $.verb = "delete" && $.objectRef.resource = "deployments" }

Result:
User: arn:aws:iam::526247032255:user/Alberuni
Time: 2026-09-25T18:22:00Z
Action: delete deployment/payment-service
Namespace: production
```

Audit logs turn Kubernetes from a black box into an accountable system.

---

## Cluster Lifecycle Management

### Provisioning

Terraform creates and manages the EKS cluster.
All configuration is version controlled in Git.

### Updates

Kubernetes version updates → change Terraform variable → apply
Add-on version updates → change add-on version in Terraform → apply
Node group updates → Terraform triggers rolling replacement

### Deletion

```
terraform destroy
```

Destroys in correct order:
1. Workloads (Argo CD removes them)
2. Node groups
3. EKS cluster
4. VPC and networking

### Disaster Recovery

Control plane: AWS manages recovery automatically.
Worker nodes: Cluster Autoscaler replaces failed nodes.
State: etcd is backed up by AWS automatically.
Terraform state: Stored in S3 with versioning enabled.
