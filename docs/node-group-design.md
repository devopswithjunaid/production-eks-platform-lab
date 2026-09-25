# Node Group Design

## Purpose

This document defines how EKS worker nodes are organized,
what runs on each group, and the decisions behind instance type
selection, scaling, and scheduling.

---

## Node Group Architecture

```
EKS Cluster
│
├── system-node-group
│   Platform controllers and cluster-critical components
│
├── application-node-group
│   Application microservices workloads
│
├── monitoring-node-group
│   Prometheus, Grafana, Loki, OpenTelemetry
│
└── security-node-group
    Falco, Kyverno, security scanning tools
```

Separating workloads across node groups provides:

- Isolation between platform tools and application workloads
- Independent scaling per workload type
- Dedicated resources for monitoring (prevents starvation)
- Ability to use different instance types per purpose

---

## System Node Group

### Purpose

Runs cluster-critical platform components that must always be available.

### Workloads

| Component               | Type        | Why here                             |
|-------------------------|-------------|--------------------------------------|
| CoreDNS                 | Deployment  | Cluster DNS — must always run        |
| kube-proxy              | DaemonSet   | Node-level networking                |
| AWS Load Balancer Controller | Deployment | Manages ALBs                    |
| ExternalDNS             | Deployment  | Route53 record management            |
| Cert Manager            | Deployment  | TLS certificate management           |
| Metrics Server          | Deployment  | Required by HPA                      |
| Cluster Autoscaler      | Deployment  | Node scaling                         |
| EBS CSI Driver          | DaemonSet   | EBS volume management                |

### Configuration

| Setting         | Value                                   |
|-----------------|-----------------------------------------|
| Instance type   | t3.medium (dev) / m5.large (prod)       |
| Min nodes       | 2                                       |
| Max nodes       | 4                                       |
| Capacity type   | On-Demand                               |
| Multi-AZ        | Yes — nodes spread across AZ-A, AZ-B, AZ-C |

### Taints and Labels

```yaml
labels:
  role: system

taints:
  - key: "node-role"
    value: "system"
    effect: "NoSchedule"
```

System workloads must carry the matching toleration to schedule here.
This prevents application pods from consuming system node capacity.

---

## Application Node Group

### Purpose

Runs all application microservices.

### Workloads

| Service           | Type       |
|-------------------|------------|
| Frontend          | Deployment |
| Checkout Service  | Deployment |
| Payment Service   | Deployment |
| Cart Service      | Deployment |
| Product Catalog   | Deployment |
| Order Service     | Deployment |

### Configuration

| Setting         | Value                                    |
|-----------------|------------------------------------------|
| Instance type   | t3.large (dev) / m5.xlarge (prod)        |
| Min nodes       | 2                                        |
| Max nodes       | 10                                       |
| Capacity type   | On-Demand (dev) / On-Demand + Spot (prod)|
| Multi-AZ        | Yes                                      |

### Scaling Strategy

Horizontal Pod Autoscaler (HPA) scales pods based on CPU/memory.
Cluster Autoscaler scales nodes when pods are pending due to resource limits.

### Labels

```yaml
labels:
  role: application
```

---

## Monitoring Node Group

### Purpose

Dedicated resources for the observability stack. Prevents Prometheus
or Loki from consuming resources that application pods need.

### Workloads

| Component              | Type        |
|------------------------|-------------|
| Prometheus             | StatefulSet |
| Grafana                | Deployment  |
| Alertmanager           | StatefulSet |
| Loki                   | StatefulSet |
| Tempo                  | Deployment  |
| OpenTelemetry Collector| Deployment  |

### Configuration

| Setting         | Value                                    |
|-----------------|------------------------------------------|
| Instance type   | t3.large (dev) / m5.xlarge (prod)        |
| Min nodes       | 1 (dev) / 2 (prod)                       |
| Max nodes       | 3                                        |
| Capacity type   | On-Demand                                |
| Multi-AZ        | Yes                                      |

### Taints and Labels

```yaml
labels:
  role: monitoring

taints:
  - key: "node-role"
    value: "monitoring"
    effect: "NoSchedule"
```

---

## Security Node Group

### Purpose

Runs security tooling with dedicated resources and isolation.

### Workloads

| Component   | Type       |
|-------------|------------|
| Falco       | DaemonSet  |
| Kyverno     | Deployment |
| Trivy       | Job / CronJob |

### Configuration

| Setting         | Value                           |
|-----------------|---------------------------------|
| Instance type   | t3.medium (dev)                 |
| Min nodes       | 1                               |
| Max nodes       | 2                               |
| Capacity type   | On-Demand                       |
| Multi-AZ        | Yes                             |

---

## Instance Type Selection Rationale

| Node Group    | Dev Instance  | Prod Instance  | Reason                              |
|---------------|---------------|----------------|-------------------------------------|
| System        | t3.medium     | m5.large       | Burstable OK in dev, stable in prod |
| Application   | t3.large      | m5.xlarge      | More vCPU/RAM for app density       |
| Monitoring    | t3.large      | m5.xlarge      | Prometheus is memory intensive      |
| Security      | t3.medium     | t3.large       | Lightweight tools                   |

---

## On-Demand vs Spot

| Environment | Strategy                                               |
|-------------|--------------------------------------------------------|
| Development | On-Demand only (simplicity, avoid interruptions)       |
| Production  | System/Monitoring: On-Demand. Application: mixed Spot  |

Spot instances can reduce application node costs by 60-80% in production
when combined with proper pod disruption budgets and multi-AZ placement.

---

## Node Lifecycle and Updates

- Managed node groups support rolling updates
- Nodes are drained before termination
- New node launches before old node is removed
- PodDisruptionBudgets protect application availability during updates
