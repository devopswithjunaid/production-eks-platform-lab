# Kubernetes Workload Design

## Purpose

This document defines how each application service is deployed
on Kubernetes — workload type, resource requirements, health checks,
scaling, and security posture.

---

## Workload Types Reference

| Type        | Use Case                                             |
|-------------|------------------------------------------------------|
| Deployment  | Stateless services — most microservices              |
| StatefulSet | Stateful services — Prometheus, databases, queues    |
| DaemonSet   | Per-node agents — Falco, log collectors, kube-proxy  |
| Job         | One-time batch tasks — migrations, SBOM generation   |
| CronJob     | Scheduled batch tasks — reports, cache warmup        |

---

## Application Services

Our e-commerce platform consists of:

```
┌─────────────────────────────────────────────┐
│              Frontend Service               │
│         (React / Next.js / Nginx)           │
└──────────────────────┬──────────────────────┘
                       │
          ┌────────────┼────────────┐
          ▼            ▼            ▼
  ┌──────────────┐ ┌──────────┐ ┌──────────────┐
  │   Product    │ │   Cart   │ │   Checkout   │
  │   Catalog    │ │ Service  │ │   Service    │
  └──────────────┘ └──────────┘ └──────┬───────┘
                                        │
                               ┌────────▼───────┐
                               │    Payment     │
                               │    Service     │
                               └────────────────┘
          │                         │
          ▼                         ▼
   ┌─────────────┐          ┌──────────────┐
   │  PostgreSQL  │          │  Redis Cache │
   │  (RDS)       │          │ (ElastiCache)│
   └─────────────┘          └──────────────┘
```

---

## Service Designs

### Frontend Service

| Property        | Value                                   |
|-----------------|-----------------------------------------|
| Workload type   | Deployment                              |
| Replicas        | min: 2, max: 8                          |
| Instance group  | application-node-group                  |
| CPU request     | 100m                                    |
| CPU limit       | 500m                                    |
| Memory request  | 128Mi                                   |
| Memory limit    | 256Mi                                   |
| Liveness probe  | HTTP GET /healthz                       |
| Readiness probe | HTTP GET /ready                         |
| Scaling trigger | CPU > 60%                               |
| Service type    | ClusterIP (exposed via Ingress/ALB)     |
| Security context| Non-root, read-only filesystem          |

---

### Product Catalog Service

| Property        | Value                                   |
|-----------------|-----------------------------------------|
| Workload type   | Deployment                              |
| Replicas        | min: 2, max: 6                          |
| Instance group  | application-node-group                  |
| CPU request     | 200m                                    |
| CPU limit       | 1000m                                   |
| Memory request  | 256Mi                                   |
| Memory limit    | 512Mi                                   |
| Liveness probe  | HTTP GET /health                        |
| Readiness probe | HTTP GET /ready                         |
| Scaling trigger | CPU > 70%                               |
| Service type    | ClusterIP                               |
| Security context| Non-root, read-only filesystem          |

---

### Cart Service

| Property        | Value                                   |
|-----------------|-----------------------------------------|
| Workload type   | Deployment                              |
| Replicas        | min: 2, max: 6                          |
| Instance group  | application-node-group                  |
| CPU request     | 100m                                    |
| CPU limit       | 500m                                    |
| Memory request  | 128Mi                                   |
| Memory limit    | 256Mi                                   |
| Liveness probe  | HTTP GET /health                        |
| Readiness probe | HTTP GET /ready                         |
| Scaling trigger | CPU > 60%                               |
| Service type    | ClusterIP                               |
| Depends on      | Redis (ElastiCache)                     |

---

### Checkout Service

| Property        | Value                                   |
|-----------------|-----------------------------------------|
| Workload type   | Deployment                              |
| Replicas        | min: 2, max: 6                          |
| Instance group  | application-node-group                  |
| CPU request     | 200m                                    |
| CPU limit       | 1000m                                   |
| Memory request  | 256Mi                                   |
| Memory limit    | 512Mi                                   |
| Liveness probe  | HTTP GET /health                        |
| Readiness probe | HTTP GET /ready                         |
| Scaling trigger | CPU > 70%                               |
| Service type    | ClusterIP                               |
| Depends on      | Cart Service, Payment Service           |

---

### Payment Service

| Property        | Value                                   |
|-----------------|-----------------------------------------|
| Workload type   | Deployment                              |
| Replicas        | min: 2, max: 4                          |
| Instance group  | application-node-group                  |
| CPU request     | 200m                                    |
| CPU limit       | 1000m                                   |
| Memory request  | 256Mi                                   |
| Memory limit    | 512Mi                                   |
| Liveness probe  | HTTP GET /health                        |
| Readiness probe | HTTP GET /ready                         |
| Scaling trigger | CPU > 70%                               |
| Service type    | ClusterIP                               |
| Security context| Non-root, read-only filesystem, no privilege escalation |

---

## Database Layer

| Component    | Type          | Managed by   | Location              |
|--------------|---------------|--------------|-----------------------|
| PostgreSQL   | Amazon RDS    | AWS          | Private Data Subnet   |
| Redis Cache  | ElastiCache   | AWS          | Private Data Subnet   |

Pods connect to RDS and ElastiCache via internal DNS names.
No pod has a direct internet route to data services.
Credentials are stored in Kubernetes Secrets (later Vault).

---

## Kubernetes Resource Standards

All deployments must define:

```yaml
resources:
  requests:
    cpu: "Xm"
    memory: "XMi"
  limits:
    cpu: "Xm"
    memory: "XMi"
```

Omitting resource requests/limits causes:
- Unpredictable scheduling
- Node overcommit
- OOMKill events
- Cluster instability

---

## Health Check Standards

All deployments must define:

```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 30
  periodSeconds: 10
  failureThreshold: 3

readinessProbe:
  httpGet:
    path: /ready
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 5
  failureThreshold: 3
```

- Liveness: Is the pod alive? Kill and restart if failing.
- Readiness: Is the pod ready to serve traffic? Remove from Service if failing.

---

## Security Context Standards

All deployments must define:

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  readOnlyRootFilesystem: true
  allowPrivilegeEscalation: false
  capabilities:
    drop:
      - ALL
```

---

## HorizontalPodAutoscaler

HPA will be applied to all application services.

Minimum configuration:

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

Two replicas minimum ensures no single point of failure.
