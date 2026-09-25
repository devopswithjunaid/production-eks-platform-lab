# EKS Node Group Design

## Node Strategy

We will NOT put all workloads on a single node group.

Different workloads have different characteristics:

- System components must always be available
- Applications must scale with traffic
- Monitoring must not be starved by application load

Mixing them on the same nodes creates resource contention,
unpredictable behaviour, and difficult troubleshooting.

### Node Group Architecture

```
EKS Cluster
│
├── system-node-group
│   └── Core platform components
│       (CoreDNS, LB Controller, ExternalDNS, Metrics Server)
│
├── application-node-group
│   └── Business workloads
│       (Frontend, Checkout, Payment, Cart, Product Catalog)
│
└── monitoring-node-group
    └── Observability stack
        (Prometheus, Grafana, Loki, Tempo, OpenTelemetry)
```

---

## System Node Group

### Purpose

Run Kubernetes core components and platform controllers.
These must remain stable and available at all times.

### Workloads

| Component                  | Type        | Why it runs here                     |
|----------------------------|-------------|--------------------------------------|
| CoreDNS                    | Deployment  | Cluster DNS — required by everything |
| kube-proxy                 | DaemonSet   | Node-level iptables networking        |
| AWS Load Balancer Controller| Deployment | Creates and manages ALBs             |
| ExternalDNS                | Deployment  | Manages Route53 DNS records          |
| Cert Manager               | Deployment  | TLS certificate automation           |
| Metrics Server             | Deployment  | Required by HPA for pod scaling      |
| Cluster Autoscaler / Karpenter | Deployment | Manages node scaling              |
| EBS CSI Driver             | DaemonSet   | EBS volume management for PVCs       |

### Node Configuration

| Setting           | Development        | Production         |
|-------------------|--------------------|--------------------|
| Instance type     | t3.medium          | m5.large           |
| Min nodes         | 2                  | 2                  |
| Max nodes         | 4                  | 6                  |
| Capacity type     | On-Demand          | On-Demand          |
| Multi-AZ          | Yes (AZ-A, B, C)   | Yes (AZ-A, B, C)   |
| EBS volume        | 20 GB gp3          | 50 GB gp3          |

On-Demand only — system components cannot be interrupted.

### Labels and Taints

```yaml
# Labels applied to all nodes in this group
labels:
  node-group: system
  workload: platform

# Taint prevents application pods from scheduling here
taints:
  - key: "node-group"
    value: "system"
    effect: "NoSchedule"
```

System workloads carry the matching toleration:

```yaml
tolerations:
  - key: "node-group"
    operator: "Equal"
    value: "system"
    effect: "NoSchedule"
```

### Why taint system nodes?

Without taints, application pods can schedule on system nodes.
Under high application load, system nodes run out of CPU/memory.
CoreDNS gets evicted. Cluster DNS breaks. Everything stops resolving.
All services fail — not because of the application, but because
a system component was evicted by an application pod.

Taints prevent this completely.

---

## Application Node Group

### Purpose

Run all business-logic microservices.
These nodes must scale up and down with traffic demand.

### Workloads

| Service             | Type       | Min Replicas | Max Replicas |
|---------------------|------------|--------------|--------------|
| Frontend            | Deployment | 2            | 8            |
| Product Catalog     | Deployment | 2            | 6            |
| Cart Service        | Deployment | 2            | 6            |
| Checkout Service    | Deployment | 2            | 6            |
| Payment Service     | Deployment | 2            | 4            |

### Node Configuration

| Setting           | Development        | Production              |
|-------------------|--------------------|-------------------------|
| Instance type     | t3.large           | m5.xlarge               |
| Min nodes         | 2                  | 3                       |
| Max nodes         | 8                  | 20                      |
| Capacity type     | On-Demand          | On-Demand + Spot mix    |
| Multi-AZ          | Yes                | Yes                     |
| EBS volume        | 20 GB gp3          | 50 GB gp3               |

### Spot instance strategy (Production only)

Spot instances provide 60-80% cost reduction.
They can be interrupted with 2-minute warning.

Safe to use because:
- Multiple replicas per service (min 2)
- PodDisruptionBudgets allow only 1 disruption at a time
- Karpenter handles graceful draining before termination
- New pods schedule on remaining On-Demand or new Spot nodes

### Labels

```yaml
labels:
  node-group: application
  workload: application
```

No taints on application nodes — they are the default landing zone
for workloads that do not specify a node group.

---

## Monitoring Node Group

### Purpose

Run the complete observability stack with dedicated resources.

### Why a dedicated monitoring node group?

Consider this scenario:

```
Application receives traffic spike
        │
        ▼
Application pods consume all available CPU on shared nodes
        │
        ▼
Prometheus gets CPU throttled — scrape intervals delayed
        │
        ▼
Metrics stop updating
        │
        ▼
Alerts fire late or not at all
        │
        ▼
Team has no visibility during the incident that caused the spike
```

Monitoring must be isolated from application resource pressure.
When you need monitoring most (during incidents), it must remain available.

### Workloads

| Component              | Type        | Storage        |
|------------------------|-------------|----------------|
| Prometheus             | StatefulSet | 50GB EBS gp3   |
| Grafana                | Deployment  | 5GB EBS gp3    |
| Alertmanager           | StatefulSet | 5GB EBS gp3    |
| Loki                   | StatefulSet | 100GB EBS gp3  |
| Tempo                  | Deployment  | 20GB EBS gp3   |
| OpenTelemetry Collector| Deployment  | —              |

### Node Configuration

| Setting           | Development        | Production         |
|-------------------|--------------------|--------------------|
| Instance type     | t3.large           | m5.xlarge          |
| Min nodes         | 1                  | 2                  |
| Max nodes         | 3                  | 5                  |
| Capacity type     | On-Demand          | On-Demand          |
| Multi-AZ          | Yes                | Yes                |
| EBS volume        | 50 GB gp3          | 100 GB gp3         |

### Labels and Taints

```yaml
labels:
  node-group: monitoring
  workload: monitoring

taints:
  - key: "node-group"
    value: "monitoring"
    effect: "NoSchedule"
```

Only monitoring workloads with matching tolerations can schedule here.

---

## Scaling Strategy

Three independent scaling layers work together:

### Layer 1 — Pod Scaling (Horizontal Pod Autoscaler)

```
Traffic increases
      │
      ▼
Pod CPU usage exceeds 70%
      │
      ▼
HPA detects metric threshold breach
(via Metrics Server)
      │
      ▼
HPA increases replica count
      │
      ▼
New pods scheduled on existing nodes
```

Example HPA configuration:

```yaml
minReplicas: 2
maxReplicas: 8
metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

### Layer 2 — Node Scaling (Karpenter)

```
Pod cannot be scheduled
(no node has enough capacity)
      │
      ▼
Karpenter detects Pending pod
      │
      ▼
Karpenter provisions new EC2 node
(right-sized for the pending pod)
      │
      ▼
Pod schedules on new node
      │
      ▼
(Traffic drops)
      │
      ▼
Karpenter detects underutilized nodes
      │
      ▼
Karpenter consolidates and terminates spare nodes
```

Why Karpenter over Cluster Autoscaler?

| Feature               | Cluster Autoscaler    | Karpenter            |
|-----------------------|-----------------------|----------------------|
| Provisioning speed    | 3-5 minutes           | Under 60 seconds     |
| Instance flexibility  | Fixed node group types| Any instance type    |
| Right-sizing          | No                    | Yes                  |
| Consolidation         | Limited               | Aggressive           |

We will start with Cluster Autoscaler (simpler) and migrate to
Karpenter when the platform is more mature.

### Layer 3 — Application Scaling (Business Level)

```
Marketing campaign launches
      │
      ▼
Traffic increases 10x
      │
      ▼
HPA scales pods (Layer 1)
      │
      ▼
Nodes fill up — Karpenter adds nodes (Layer 2)
      │
      ▼
Campaign ends — traffic drops
      │
      ▼
HPA scales pods down
      │
      ▼
Karpenter consolidates and removes spare nodes
```

The combination of HPA + Karpenter handles most real-world
traffic patterns automatically with no manual intervention.

---

## Scheduling Rules

### Node Selector

Pods declare which node group they want:

```yaml
nodeSelector:
  node-group: application
```

### Topology Spread

Pods spread across AZs automatically:

```yaml
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: DoNotSchedule
    labelSelector:
      matchLabels:
        app: checkout-service
```

This ensures no single AZ runs all replicas of a service.
If AZ-A fails, replicas in AZ-B and AZ-C continue serving traffic.

### Pod Anti-Affinity

Prefer spreading replicas across different nodes:

```yaml
affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector:
            matchLabels:
              app: checkout-service
          topologyKey: kubernetes.io/hostname
```

Two replicas of the same service should not run on the same node.
If a node fails, only one replica is lost — not all of them.

---

## Node Group Summary

| Node Group     | Instance (Dev) | Instance (Prod) | Capacity  | Min | Max |
|----------------|----------------|-----------------|-----------|-----|-----|
| System         | t3.medium      | m5.large        | On-Demand | 2   | 4   |
| Application    | t3.large       | m5.xlarge       | On-Demand + Spot | 2 | 20 |
| Monitoring     | t3.large       | m5.xlarge       | On-Demand | 1   | 5   |
