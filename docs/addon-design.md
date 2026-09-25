# Add-on Design

## Purpose

This document catalogs every add-on that will be installed on the cluster,
why it exists, who manages it, and how it is installed.

---

## Add-on Categories

```
EKS Add-ons
│
├── AWS Managed Add-ons (via EKS API)
│   ├── VPC CNI
│   ├── CoreDNS
│   ├── kube-proxy
│   └── EBS CSI Driver
│
├── Networking
│   ├── AWS Load Balancer Controller
│   ├── ExternalDNS
│   └── Cert Manager
│
├── GitOps
│   ├── Argo CD
│   └── Argo Rollouts
│
├── Security
│   ├── HashiCorp Vault
│   ├── Kyverno
│   └── Falco
│
└── Monitoring
    ├── Prometheus
    ├── Grafana
    ├── Alertmanager
    ├── Loki
    ├── Tempo
    └── OpenTelemetry Collector
```

---

## AWS Managed Add-ons

### VPC CNI (aws-node)

| Property    | Value                                         |
|-------------|-----------------------------------------------|
| Managed by  | AWS EKS managed add-on                        |
| Installed   | Terraform (aws_eks_addon resource)            |
| Purpose     | Assigns real VPC IP addresses to every Pod    |

Every Pod gets a real VPC subnet IP. This enables direct VPC-native
routing without overlay networks. Required for EKS.

---

### CoreDNS

| Property    | Value                                         |
|-------------|-----------------------------------------------|
| Managed by  | AWS EKS managed add-on                        |
| Installed   | Terraform                                     |
| Purpose     | Cluster DNS — resolves service names to IPs   |

Every Kubernetes Service gets a DNS name:
`<service>.<namespace>.svc.cluster.local`

CoreDNS resolves these names to ClusterIP addresses.
Without CoreDNS, inter-service communication by name breaks completely.

---

### kube-proxy

| Property    | Value                                         |
|-------------|-----------------------------------------------|
| Managed by  | AWS EKS managed add-on                        |
| Installed   | Terraform                                     |
| Purpose     | Manages iptables rules for Service routing    |

kube-proxy runs as a DaemonSet on every node. It translates
ClusterIP Service addresses to Pod IPs using iptables rules.

---

### EBS CSI Driver

| Property    | Value                                         |
|-------------|-----------------------------------------------|
| Managed by  | AWS EKS managed add-on                        |
| Installed   | Terraform                                     |
| Purpose     | Enables EBS volumes as PersistentVolumes       |

Required for any stateful workload that needs persistent disk storage.
Prometheus uses EBS for metric storage.

---

## Networking Add-ons

### AWS Load Balancer Controller

| Property    | Value                                         |
|-------------|-----------------------------------------------|
| Managed by  | Helm (Argo CD managed)                        |
| Namespace   | kube-system                                   |
| Node group  | system-node-group                             |
| Purpose     | Creates ALBs and NLBs from Kubernetes Ingress |

When an Ingress resource is created, this controller provisions
an Application Load Balancer in AWS automatically.
The controller uses EKS Pod Identity to call the AWS ELB API.

---

### ExternalDNS

| Property    | Value                                         |
|-------------|-----------------------------------------------|
| Managed by  | Helm (Argo CD managed)                        |
| Namespace   | kube-system                                   |
| Node group  | system-node-group                             |
| Purpose     | Creates Route 53 records for Ingress/Services |

When an Ingress is annotated, ExternalDNS automatically creates or
updates the Route 53 DNS record to point to the ALB DNS name.

---

### Cert Manager

| Property    | Value                                         |
|-------------|-----------------------------------------------|
| Managed by  | Helm (Argo CD managed)                        |
| Namespace   | cert-manager                                  |
| Node group  | system-node-group                             |
| Purpose     | Automatic TLS certificate provisioning        |

Provisions TLS certificates from Let's Encrypt using DNS-01 validation
via Route 53. Certificates are stored as Kubernetes Secrets and
automatically renewed before expiry.

---

## GitOps Add-ons

### Argo CD

| Property    | Value                                         |
|-------------|-----------------------------------------------|
| Managed by  | Helm (bootstrapped via Terraform or manually) |
| Namespace   | argocd                                        |
| Node group  | system-node-group                             |
| Purpose     | GitOps continuous delivery for all workloads  |

Argo CD watches the GitOps repository. When desired state in Git
differs from actual state in the cluster, Argo CD reconciles
the cluster back to the desired state automatically.

After Argo CD is installed, it manages all other add-ons via
ApplicationSets.

---

### Argo Rollouts

| Property    | Value                                         |
|-------------|-----------------------------------------------|
| Managed by  | Argo CD ApplicationSet                        |
| Namespace   | argo-rollouts                                 |
| Node group  | system-node-group                             |
| Purpose     | Canary and Blue/Green deployment strategies   |

Extends Kubernetes Deployments with advanced rollout strategies.
Enables progressive delivery with automatic rollback on failure metrics.

---

## Security Add-ons

### HashiCorp Vault

| Property    | Value                                         |
|-------------|-----------------------------------------------|
| Managed by  | Argo CD                                       |
| Namespace   | vault                                         |
| Node group  | security-node-group                           |
| Purpose     | Centralized dynamic secret management         |

Vault will be introduced after studying Kubernetes-native Secrets.
Provides dynamic credentials, secret versioning, audit logging, and
fine-grained access policies.

---

### Kyverno

| Property    | Value                                         |
|-------------|-----------------------------------------------|
| Managed by  | Argo CD                                       |
| Namespace   | kyverno                                       |
| Node group  | security-node-group                           |
| Purpose     | Kubernetes-native admission policy engine     |

Enforces policies such as:
- All containers must define resource limits
- Images must be signed
- No privileged containers
- Labels must be present

Kyverno can also generate and mutate resources on admission.

---

### Falco

| Property    | Value                                         |
|-------------|-----------------------------------------------|
| Managed by  | Argo CD                                       |
| Namespace   | security                                      |
| Node group  | security-node-group                           |
| Purpose     | Runtime threat detection                      |
| Type        | DaemonSet (runs on every node)                |

Falco monitors system calls at the kernel level and alerts on
suspicious behaviour such as:
- Shell spawned inside a container
- Unexpected network connections
- File access in sensitive directories

---

## Monitoring Add-ons

### Prometheus

| Property    | Value                              |
|-------------|-------------------------------------|
| Managed by  | Argo CD (kube-prometheus-stack)     |
| Namespace   | monitoring                          |
| Node group  | monitoring-node-group               |
| Purpose     | Metrics collection and storage      |
| Type        | StatefulSet (persistent EBS storage)|

---

### Grafana

| Property    | Value                              |
|-------------|-------------------------------------|
| Managed by  | Argo CD (kube-prometheus-stack)     |
| Namespace   | monitoring                          |
| Node group  | monitoring-node-group               |
| Purpose     | Metrics dashboards and visualization|

---

### Alertmanager

| Property    | Value                              |
|-------------|-------------------------------------|
| Managed by  | Argo CD (kube-prometheus-stack)     |
| Namespace   | monitoring                          |
| Node group  | monitoring-node-group               |
| Purpose     | Alert routing and notification      |

---

### Loki

| Property    | Value                              |
|-------------|-------------------------------------|
| Managed by  | Argo CD (loki-stack)                |
| Namespace   | monitoring                          |
| Node group  | monitoring-node-group               |
| Purpose     | Log aggregation and querying        |

---

### OpenTelemetry Collector

| Property    | Value                              |
|-------------|-------------------------------------|
| Managed by  | Argo CD                             |
| Namespace   | monitoring                          |
| Node group  | monitoring-node-group               |
| Purpose     | Distributed tracing collection      |

---

## Add-on Installation Order

1. VPC CNI, CoreDNS, kube-proxy, EBS CSI (Terraform — before cluster is usable)
2. AWS Load Balancer Controller (Helm — needed before Ingress works)
3. Argo CD (Helm — bootstrapped manually or via Terraform)
4. All remaining add-ons (Argo CD ApplicationSets — GitOps managed)
