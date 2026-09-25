# EKS Cluster Design

## Purpose

This document defines how the Amazon EKS cluster is configured,
what AWS manages, what we manage, and the key decisions made
before provisioning.

---

## EKS Version Strategy

| Decision            | Choice                                |
|---------------------|---------------------------------------|
| Initial version     | Latest stable EKS release             |
| Upgrade strategy    | Minor version upgrade annually        |
| Add-on versions     | Independently managed per addon       |

AWS typically supports three Kubernetes minor versions at a time.
We will track the latest stable version and upgrade on a planned schedule.

Kubernetes version will be defined as a Terraform variable so it can be
updated in one place and applied cleanly.

---

## Control Plane

### What AWS manages

- Kubernetes API server
- etcd (distributed state store)
- Controller Manager
- Scheduler
- Control plane high availability
- Control plane patching and upgrades

We do not SSH into the control plane.
We do not manage etcd directly.
We do not manage control plane scaling.

### What we manage

- EKS cluster configuration
- Managed node groups
- Add-ons
- Cluster authentication (aws-auth or EKS Access Entries)
- RBAC within the cluster
- Workloads running on the cluster

### Control plane failure

If the Kubernetes control plane fails:

- Running pods are NOT affected (they keep running)
- No new pods can be scheduled
- No deployments can be modified
- No scaling events will trigger
- Kubernetes health checks keep restarting pods on nodes

AWS SLA guarantees control plane availability. Recovery is automatic.

---

## API Endpoint Configuration

```
EKS API Endpoint
├── Private access: ENABLED
└── Public access:  ENABLED (initially)
```

### Rationale

- Private endpoint keeps node-to-control-plane traffic inside the VPC
- Public endpoint allows administrator access without VPN
- Public endpoint will be restricted to trusted CIDR ranges

### Future state

```
EKS API Endpoint
├── Private access: ENABLED
└── Public access:  DISABLED
```

Requires VPN or bastion access into the VPC.

---

## Cluster Networking

| Setting              | Value                     |
|----------------------|---------------------------|
| VPC                  | 10.20.0.0/16              |
| CNI                  | AWS VPC CNI               |
| Service CIDR         | 172.20.0.0/16             |
| Pod networking       | VPC-native (real VPC IPs) |
| DNS                  | CoreDNS                   |
| Proxy mode           | kube-proxy (iptables)     |

### AWS VPC CNI behaviour

Every Pod receives a real IP address from the VPC subnet.
This means:

- Pod IPs are routable within the VPC with no overlay network
- Pod IPs consume real VPC subnet address space
- EKS subnets must be large enough to support nodes AND pods

This is why our private EKS subnets are /20 (4096 IPs) rather than /24 (256 IPs).

---

## Authentication Method

| Actor             | Authentication Method              |
|-------------------|------------------------------------|
| Engineers         | AWS IAM via kubeconfig             |
| GitHub Actions    | GitHub OIDC → IAM Role → EKS       |
| Pods              | EKS Pod Identity (IRSA successor)  |

EKS Access Entries will be used instead of manual aws-auth ConfigMap editing.
This is the AWS-recommended modern authentication approach.

---

## Control Plane Logging

The following control plane log types will be enabled:

| Log Type       | Purpose                                 |
|----------------|-----------------------------------------|
| api            | All API server requests                 |
| audit          | Who did what to which resource          |
| authenticator  | IAM authentication events               |
| controllerManager | Reconciliation loops and decisions   |
| scheduler      | Pod scheduling decisions                |

Logs are sent to Amazon CloudWatch Logs.

---

## EKS Add-on Management

EKS managed add-ons will be used where available (VPC CNI, CoreDNS, kube-proxy, EBS CSI).

Self-managed Helm-based add-ons will be used for platform tools (Argo CD, Prometheus, Vault, etc.).

Add-ons are documented separately in: `docs/addon-design.md`

---

## Summary of Key Decisions

| Decision                        | Choice                                  |
|---------------------------------|-----------------------------------------|
| Control plane                   | AWS managed (EKS)                       |
| Kubernetes version              | Latest stable, defined as variable      |
| API endpoint                    | Public + Private initially              |
| CNI                             | AWS VPC CNI                             |
| Authentication                  | EKS Access Entries + Pod Identity       |
| Control plane logging           | All log types enabled → CloudWatch      |
| Add-on management               | EKS managed + Helm (Argo CD managed)    |
