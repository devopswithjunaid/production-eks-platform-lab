# Observability Design

## Purpose

Design the complete observability stack before installing any tools.
Know what we are measuring, why we are measuring it, and what
should wake an engineer at 2 AM.

---

## Observability Pillars

```
┌─────────────────────────────────────────────┐
│              OBSERVABILITY                  │
│                                             │
│  Metrics     Logs        Traces             │
│  (What)      (Why)       (Where)            │
│                                             │
│  Prometheus  Loki        OpenTelemetry      │
│  Grafana     Loki        Tempo              │
│  Alertmanager            Grafana            │
└─────────────────────────────────────────────┘
```

---

## Metrics — Prometheus

### What Prometheus collects

#### Infrastructure metrics

| Metric                         | Source             |
|--------------------------------|--------------------|
| Node CPU utilization           | node-exporter      |
| Node memory utilization        | node-exporter      |
| Node disk utilization          | node-exporter      |
| Node network I/O               | node-exporter      |
| Pod CPU usage                  | cAdvisor (kubelet) |
| Pod memory usage               | cAdvisor (kubelet) |
| Pod restart count              | kube-state-metrics |
| Pending pod count              | kube-state-metrics |
| Node condition (Ready/NotReady)| kube-state-metrics |

#### Kubernetes metrics

| Metric                             | Source             |
|------------------------------------|--------------------|
| Deployment replica count           | kube-state-metrics |
| HPA current/desired replicas       | kube-state-metrics |
| PVC bound/pending status           | kube-state-metrics |
| Job success/failure                | kube-state-metrics |
| API server request latency         | kube-apiserver     |

#### Application metrics (custom)

| Metric                        | Description                        |
|-------------------------------|------------------------------------|
| http_request_duration_seconds | HTTP latency histogram per service |
| http_requests_total           | Request count by status code       |
| http_errors_total             | Error count by type                |
| db_query_duration_seconds     | Database query latency             |
| checkout_orders_total         | Business metric: orders processed  |
| payment_failures_total        | Business metric: payment errors    |

All application services must expose a `/metrics` endpoint
in Prometheus exposition format.

---

## Logs — Loki

### What Loki collects

| Source                  | Content                                   |
|-------------------------|-------------------------------------------|
| Application containers  | Structured JSON logs from each service    |
| Kubernetes events       | Pod scheduling, OOMKill, image pull errors|
| Control plane audit logs| Who did what in the cluster (CloudWatch)  |
| Ingress controller logs | HTTP access logs, error logs              |
| Falco alerts            | Runtime security events                   |

### Log format standard

All application services must emit structured JSON logs:

```json
{
  "timestamp": "2025-09-25T01:00:00Z",
  "level": "ERROR",
  "service": "payment-service",
  "trace_id": "abc123",
  "message": "Payment gateway timeout",
  "duration_ms": 5000,
  "order_id": "ord-789"
}
```

Structured logs enable efficient querying in Loki using LogQL.

---

## Tracing — OpenTelemetry + Tempo

### What tracing shows

```
User Request
   │  trace_id: abc123
   ├── Frontend Service        (20ms)
   │       │
   │       ├── Checkout Service  (180ms)
   │       │       │
   │       │       ├── Payment Service  (150ms ← SLOW)
   │       │       │       │
   │       │       │       └── Payment Gateway API (145ms)
   │       │       │
   │       │       └── Cart Service    (5ms)
   │       │
   │       └── Product Catalog (10ms)
```

Tracing reveals exactly which service in the chain is slow.
Metrics can tell you latency is high. Traces tell you WHERE.

### OpenTelemetry Collector

Receives traces from all services → forwards to Tempo.
Also receives metrics → forwards to Prometheus.
Also receives logs → forwards to Loki.

Single collection pipeline for all three signals.

---

## Dashboards — Grafana

### Pre-built dashboards

| Dashboard                    | Purpose                                   |
|------------------------------|-------------------------------------------|
| Cluster Overview             | Node count, pod count, CPU/memory usage   |
| Node Details                 | Per-node resource breakdown               |
| Namespace Overview           | Resource usage per namespace              |
| Application Service          | Latency, error rate, throughput per service|
| Kubernetes Deployments       | Rollout status, replica health            |
| EKS Add-ons                  | Health of CoreDNS, LB Controller, etc.    |
| Business Metrics             | Orders/min, payments/min, error rates     |
| Alertmanager                 | Active alerts, alert history              |

---

## Alerts — Alertmanager

### Alert routing

```
Prometheus fires alert
       │
       ▼
Alertmanager
       │
       ├── Critical alerts → PagerDuty / Slack #incidents
       ├── Warning alerts  → Slack #platform-alerts
       └── Info alerts     → Slack #platform-info
```

### What wakes an engineer at 2 AM (Critical)

These must trigger immediate response:

| Alert                              | Threshold                   |
|------------------------------------|-----------------------------|
| Node down                          | Any node NotReady > 2 min   |
| Pod crash looping                  | Restart count > 5 in 10 min |
| High error rate                    | HTTP 5xx > 5% for 5 min     |
| High API latency                   | P99 > 2 seconds for 5 min   |
| PVC pending (storage unavailable)  | Any PVC Pending > 5 min     |
| Payment service errors             | Any payment failure spike   |
| NAT Gateway failure                | No internet egress from pods|
| Certificate expiry                 | TLS cert expires in < 7 days|
| Disk pressure on node              | Node disk > 85%             |
| Memory pressure on node            | Node memory > 90%           |

### Warning alerts (not 2 AM, but monitor)

| Alert                          | Threshold                        |
|--------------------------------|----------------------------------|
| High CPU                       | Pod CPU > 80% for 15 min         |
| High memory                    | Pod memory > 80% for 15 min      |
| HPA at max replicas            | HPA maxReplicas reached          |
| Many pending pods              | > 3 pods Pending for 5 min       |
| Slow database queries          | DB P99 > 500ms for 10 min        |

---

## Observability Stack Components

| Component              | Role                          | Managed by    |
|------------------------|-------------------------------|---------------|
| Prometheus             | Metrics scraping + storage    | Argo CD       |
| Grafana                | Dashboards + visualization    | Argo CD       |
| Alertmanager           | Alert routing + notification  | Argo CD       |
| node-exporter          | Node-level metrics            | Argo CD       |
| kube-state-metrics     | Kubernetes object metrics     | Argo CD       |
| Loki                   | Log aggregation               | Argo CD       |
| Promtail               | Log shipping (DaemonSet)      | Argo CD       |
| OpenTelemetry Collector| Trace + metric collection     | Argo CD       |
| Tempo                  | Distributed trace storage     | Argo CD       |

---

## Retention Policy

| Signal  | Development | Production |
|---------|-------------|------------|
| Metrics | 15 days     | 90 days    |
| Logs    | 7 days      | 30 days    |
| Traces  | 3 days      | 14 days    |

Control plane audit logs (CloudWatch): 90 days minimum.
