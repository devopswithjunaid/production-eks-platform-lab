# EKS Addon Design

## Overview

Addons are components installed on top of the EKS cluster that
provide functionality Kubernetes does not include by default.

Without addons, a cluster can schedule pods but cannot:
- Route internet traffic to pods (no load balancer controller)
- Provision TLS certificates automatically (no cert-manager)
- Deploy applications from Git (no Argo CD)
- Store metrics (no Prometheus)
- Detect runtime threats (no Falco)

This document catalogs every addon, explains why it exists,
who manages it, and in what order it is installed.

---

## Installation Order

The order matters — some addons depend on others.

```
Phase 1: AWS Managed Addons (Terraform)
  VPC CNI → CoreDNS → kube-proxy → EBS CSI Driver
  (Cluster is now functional)

Phase 2: Networking (Helm via Terraform or manual bootstrap)
  AWS Load Balancer Controller → ExternalDNS → Cert Manager
  (Traffic routing is now functional)

Phase 3: GitOps Bootstrap (Helm — manual first time)
  Argo CD
  (GitOps is now functional)

Phase 4: Everything else (Argo CD ApplicationSets)
  Security + Monitoring + Application addons
  (All managed declaratively via Git)
```

---

## AWS Managed Addons

These are installed and updated via the EKS API.
Terraform manages them using `aws_eks_addon` resource.

---

### VPC CNI (aws-node)

| Property       | Value                                          |
|----------------|------------------------------------------------|
| Managed by     | AWS EKS managed addon (Terraform)              |
| Namespace      | kube-system                                    |
| Type           | DaemonSet (runs on every node)                 |
| Install phase  | Phase 1 — before any workloads                 |

**Purpose:**

Assigns real VPC IP addresses to every Kubernetes Pod.

Without VPC CNI, pods cannot get IP addresses and cannot communicate.
This is the foundational networking plugin for EKS — nothing works without it.

**Why it matters:**

```
Without VPC CNI:
Pod has no IP address → Pod cannot communicate → Cluster unusable

With VPC CNI:
Pod gets real VPC IP → Pod is routable in VPC → Services communicate
```

Every node pre-allocates a pool of IPs from the subnet.
This is why EKS subnets must be large (/20 = 4096 IPs).

---

### CoreDNS

| Property       | Value                                          |
|----------------|------------------------------------------------|
| Managed by     | AWS EKS managed addon (Terraform)              |
| Namespace      | kube-system                                    |
| Type           | Deployment (2 replicas minimum)                |
| Install phase  | Phase 1                                        |

**Purpose:**

Cluster-internal DNS resolution.

Every Kubernetes Service gets a DNS name automatically:
```
<service>.<namespace>.svc.cluster.local
```

Without CoreDNS, services cannot find each other by name.
Hardcoding Pod IPs is not viable — they change every restart.

**Example:**
```
checkout-service calls: http://payment-service.dev.svc.cluster.local:8080
CoreDNS resolves it to: 172.20.14.25 (ClusterIP)
kube-proxy routes it to: actual pod IP
```

---

### kube-proxy

| Property       | Value                                          |
|----------------|------------------------------------------------|
| Managed by     | AWS EKS managed addon (Terraform)              |
| Namespace      | kube-system                                    |
| Type           | DaemonSet (runs on every node)                 |
| Install phase  | Phase 1                                        |

**Purpose:**

Manages iptables rules on every node for Service routing.

When a pod sends traffic to a ClusterIP, kube-proxy's iptables rules
translate that ClusterIP to a real Pod IP and load balance across replicas.

Without kube-proxy, Kubernetes Services do not work.

---

### EBS CSI Driver

| Property       | Value                                          |
|----------------|------------------------------------------------|
| Managed by     | AWS EKS managed addon (Terraform)              |
| Namespace      | kube-system                                    |
| Type           | DaemonSet + Deployment                         |
| Install phase  | Phase 1                                        |

**Purpose:**

Enables EBS volumes as Kubernetes PersistentVolumes.

Required for any stateful workload:
- Prometheus metrics storage
- Loki log storage
- Any StatefulSet requiring persistent disk

Without EBS CSI Driver, PersistentVolumeClaims remain Pending
and stateful workloads cannot start.

---

## Networking Addons

These are installed after the cluster is functional.
Managed by Helm charts — eventually by Argo CD.

---

### AWS Load Balancer Controller

| Property       | Value                                          |
|----------------|------------------------------------------------|
| Managed by     | Helm (Argo CD after bootstrap)                 |
| Namespace      | kube-system                                    |
| Node group     | system-node-group                              |
| Install phase  | Phase 2                                        |
| IAM            | Pod Identity → eks-load-balancer-controller-role|

**Purpose:**

Creates and manages AWS Application Load Balancers from
Kubernetes Ingress resources.

Without this controller:
- Kubernetes Ingress objects do nothing in AWS
- No external traffic can reach pods
- Applications are inaccessible from the internet

With this controller:
```
Developer creates Kubernetes Ingress
          │
          ▼
AWS Load Balancer Controller detects it
          │
          ▼
Controller calls AWS ELB API
          │
          ▼
ALB created in public subnets
          │
          ▼
Internet traffic routed to pods
```

---

### ExternalDNS

| Property       | Value                                          |
|----------------|------------------------------------------------|
| Managed by     | Helm (Argo CD)                                 |
| Namespace      | kube-system                                    |
| Node group     | system-node-group                              |
| Install phase  | Phase 2                                        |
| IAM            | Pod Identity → eks-external-dns-role           |

**Purpose:**

Automatically creates Route 53 DNS records from Kubernetes Ingress
and Service annotations.

Without ExternalDNS, engineers must manually create Route 53 records
every time a new service is deployed. Error-prone and slow.

With ExternalDNS:
```
Ingress annotated with: external-dns.alpha.kubernetes.io/hostname: app.example.com
          │
          ▼
ExternalDNS detects the annotation
          │
          ▼
ExternalDNS creates Route53 A record: app.example.com → ALB DNS name
          │
          ▼
DNS propagates automatically
```

---

### Cert Manager

| Property       | Value                                          |
|----------------|------------------------------------------------|
| Managed by     | Helm (Argo CD)                                 |
| Namespace      | cert-manager                                   |
| Node group     | system-node-group                              |
| Install phase  | Phase 2                                        |
| IAM            | Pod Identity → eks-cert-manager-role           |

**Purpose:**

Automatically provisions and renews TLS certificates from Let's Encrypt.

Without Cert Manager, engineers manually request, install, and renew
certificates. Certificates expire and cause outages if forgotten.

With Cert Manager:
```
Ingress annotated with: cert-manager.io/cluster-issuer: letsencrypt-prod
          │
          ▼
Cert Manager detects it
          │
          ▼
Requests certificate from Let's Encrypt
using Route 53 DNS validation
          │
          ▼
Certificate stored as Kubernetes Secret
          │
          ▼
Certificate auto-renewed 30 days before expiry
```

---

## GitOps Addons

---

### Argo CD

| Property       | Value                                          |
|----------------|------------------------------------------------|
| Managed by     | Helm (bootstrapped first time manually/Terraform)|
| Namespace      | argocd                                         |
| Node group     | system-node-group                              |
| Install phase  | Phase 3                                        |

**Purpose:**

GitOps continuous delivery — deploys and reconciles all Kubernetes workloads
from Git as the single source of truth.

After Argo CD is installed, it manages ALL other addons via ApplicationSets.
The cluster becomes self-managing — any drift from Git is auto-corrected.

```
Git repository (desired state)
          │
          ▼
Argo CD watches for changes
          │
          ▼
Cluster drift detected
          │
          ▼
Argo CD reconciles cluster to match Git
          │
          ▼
Cluster matches desired state
```

---

### Argo Rollouts

| Property       | Value                                          |
|----------------|------------------------------------------------|
| Managed by     | Argo CD ApplicationSet                         |
| Namespace      | argo-rollouts                                  |
| Node group     | system-node-group                              |
| Install phase  | Phase 4                                        |

**Purpose:**

Advanced deployment strategies — canary and blue/green deployments.

Standard Kubernetes Deployments do all-at-once rolling updates.
Argo Rollouts allows:

```
New version deployed to 10% of traffic
          │
    ┌─────▼──────┐
    │  Metrics OK?│
    └─────┬──────┘
    Yes   │    No
          │         └──► Automatic rollback
          ▼
Deploy to 50% of traffic
          │
    ┌─────▼──────┐
    │  Metrics OK?│
    └─────┬──────┘
          │
          ▼
Deploy to 100% of traffic
```

---

## Security Addons

---

### HashiCorp Vault

| Property       | Value                                          |
|----------------|------------------------------------------------|
| Managed by     | Argo CD                                        |
| Namespace      | vault                                          |
| Node group     | system-node-group                              |
| Install phase  | Phase 4 (after studying K8s Secrets)           |

**Purpose:**

Centralized secret management with dynamic credentials, audit logging,
secret versioning, and fine-grained access control.

Introduced after we understand Kubernetes-native Secrets and their limitations.

---

### Kyverno

| Property       | Value                                          |
|----------------|------------------------------------------------|
| Managed by     | Argo CD                                        |
| Namespace      | kyverno                                        |
| Node group     | system-node-group                              |
| Install phase  | Phase 4                                        |

**Purpose:**

Kubernetes-native policy engine — admission control.

Example policies enforced at admission time:

```
DENY: Pods without resource limits
DENY: Privileged containers
DENY: Images from untrusted registries
DENY: Missing required labels
MUTATE: Add default security context to all pods
GENERATE: Create default NetworkPolicy for new namespaces
```

Kyverno stops bad configurations before they reach the cluster.

---

### Falco

| Property       | Value                                          |
|----------------|------------------------------------------------|
| Managed by     | Argo CD                                        |
| Namespace      | security                                       |
| Node group     | system-node-group                              |
| Type           | DaemonSet (runs on every node)                 |
| Install phase  | Phase 4                                        |

**Purpose:**

Runtime threat detection at the kernel syscall level.

Falco watches system calls in real time and alerts on:

```
ALERT: Shell spawned inside a container
ALERT: Unexpected network connection from pod
ALERT: File write in /etc or /bin
ALERT: Privilege escalation attempt
ALERT: Container reading sensitive host path
```

Kyverno prevents bad configs at admission.
Falco detects bad behaviour at runtime.
Both layers are necessary.

---

## Observability Addons

---

### Prometheus

| Property   | Value                                          |
|------------|------------------------------------------------|
| Managed by | Argo CD (kube-prometheus-stack Helm chart)     |
| Namespace  | monitoring                                     |
| Node group | monitoring-node-group                          |
| Type       | StatefulSet with EBS persistent storage        |

**Purpose:** Metrics scraping, storage, and alerting rules.

---

### Grafana

| Property   | Value                                          |
|------------|------------------------------------------------|
| Managed by | Argo CD (kube-prometheus-stack)                |
| Namespace  | monitoring                                     |
| Node group | monitoring-node-group                          |

**Purpose:** Metrics dashboards and visualization.

---

### Alertmanager

| Property   | Value                                          |
|------------|------------------------------------------------|
| Managed by | Argo CD (kube-prometheus-stack)                |
| Namespace  | monitoring                                     |
| Node group | monitoring-node-group                          |

**Purpose:** Alert routing — sends alerts to Slack, PagerDuty, email.

---

### Loki

| Property   | Value                                          |
|------------|------------------------------------------------|
| Managed by | Argo CD (loki-stack Helm chart)                |
| Namespace  | monitoring                                     |
| Node group | monitoring-node-group                          |
| Type       | StatefulSet with EBS persistent storage        |

**Purpose:** Log aggregation — collects and indexes logs from all pods.

---

### Tempo

| Property   | Value                                          |
|------------|------------------------------------------------|
| Managed by | Argo CD                                        |
| Namespace  | monitoring                                     |
| Node group | monitoring-node-group                          |

**Purpose:** Distributed trace storage — stores traces from OpenTelemetry.

---

### OpenTelemetry Collector

| Property   | Value                                          |
|------------|------------------------------------------------|
| Managed by | Argo CD                                        |
| Namespace  | monitoring                                     |
| Node group | monitoring-node-group                          |

**Purpose:**

Single collection pipeline for all three observability signals:
- Receives traces from application pods → forwards to Tempo
- Receives metrics → forwards to Prometheus
- Receives logs → forwards to Loki

Applications send all telemetry to one endpoint.
The Collector fans it out to the right backend.

---

## Addon Summary Table

| Addon                      | Category    | Managed By      | Node Group     | Phase |
|----------------------------|-------------|-----------------|----------------|-------|
| VPC CNI                    | AWS Managed | Terraform        | All nodes      | 1     |
| CoreDNS                    | AWS Managed | Terraform        | System         | 1     |
| kube-proxy                 | AWS Managed | Terraform        | All nodes      | 1     |
| EBS CSI Driver             | AWS Managed | Terraform        | System         | 1     |
| AWS Load Balancer Controller| Networking  | Argo CD         | System         | 2     |
| ExternalDNS                | Networking  | Argo CD          | System         | 2     |
| Cert Manager               | Networking  | Argo CD          | System         | 2     |
| Argo CD                    | GitOps      | Helm (bootstrap) | System         | 3     |
| Argo Rollouts              | GitOps      | Argo CD          | System         | 4     |
| HashiCorp Vault            | Security    | Argo CD          | System         | 4     |
| Kyverno                    | Security    | Argo CD          | System         | 4     |
| Falco                      | Security    | Argo CD          | System         | 4     |
| Prometheus                 | Monitoring  | Argo CD          | Monitoring     | 4     |
| Grafana                    | Monitoring  | Argo CD          | Monitoring     | 4     |
| Alertmanager               | Monitoring  | Argo CD          | Monitoring     | 4     |
| Loki                       | Monitoring  | Argo CD          | Monitoring     | 4     |
| Tempo                      | Monitoring  | Argo CD          | Monitoring     | 4     |
| OpenTelemetry Collector    | Monitoring  | Argo CD          | Monitoring     | 4     |
