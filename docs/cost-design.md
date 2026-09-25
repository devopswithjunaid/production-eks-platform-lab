# Cost Design

## Purpose

Real production platforms must be cost-aware.
This document identifies the main cost drivers, documents
our development vs production cost trade-offs, and sets
guardrails to prevent surprise bills.

---

## Main Cost Areas

### 1. EKS Control Plane

| Item           | Cost                        |
|----------------|------------------------------|
| EKS Cluster    | ~\$0.10 per hour per cluster |
| Monthly        | ~\$72/month per cluster      |

There is no way to reduce this — it is a fixed cost for running EKS.
Shared across all workloads running in the cluster.

---

### 2. EC2 Worker Nodes

The largest cost driver.

| Node Group     | Dev Instance  | Dev Cost/hr | Prod Instance | Prod Cost/hr |
|----------------|---------------|-------------|---------------|--------------|
| System         | t3.medium x2  | ~\$0.08     | m5.large x2   | ~\$0.19      |
| Application    | t3.large x2   | ~\$0.17     | m5.xlarge x2  | ~\$0.38      |
| Monitoring     | t3.large x1   | ~\$0.083    | m5.xlarge x2  | ~\$0.38      |
| Security       | t3.medium x1  | ~\$0.042    | t3.large x2   | ~\$0.17      |

Development total estimate: ~\$0.375/hr → ~\$270/month (always on)

Cost optimization: **Stop dev nodes when not in use.**

---

### 3. NAT Gateway

| Environment | NAT Gateways | Cost                            |
|-------------|--------------|----------------------------------|
| Development | 1            | ~\$0.045/hr + data processing   |
| Production  | 3 (one per AZ)| ~\$0.135/hr + data processing  |

Monthly (dev): ~\$32/month fixed + data transfer costs.

NAT Gateway data processing: \$0.045 per GB processed.
High-traffic clusters can have significant NAT data costs.

**Cost reduction:** Use VPC Endpoints for AWS services (S3, ECR, STS).
Traffic to these services bypasses NAT Gateway entirely.

---

### 4. Application Load Balancer

| Item                  | Cost                                |
|-----------------------|-------------------------------------|
| ALB fixed cost        | ~\$0.008/hr per ALB                 |
| LCU (capacity units)  | ~\$0.008 per LCU-hour               |
| Monthly fixed         | ~\$5.76/month per ALB               |

One ALB can serve multiple domains and services via Ingress rules.
Use one ALB with path-based and host-based routing rather than one ALB per service.

---

### 5. Amazon EBS Volumes

| Usage           | Approximate Cost           |
|-----------------|----------------------------|
| gp3 storage     | \$0.08/GB-month            |
| Prometheus 50GB | ~\$4/month                 |
| Loki 100GB      | ~\$8/month                 |
| General storage | Depends on workload volume |

EBS snapshots for backup add additional storage costs.

---

### 6. Amazon ECR

| Item              | Cost                          |
|-------------------|-------------------------------|
| Storage           | \$0.10/GB-month               |
| Data transfer in  | Free                          |
| Data transfer out | First 500MB/month free, then \$0.09/GB |

ECR lifecycle policies reduce cost by automatically removing old images.

---

### 7. CloudWatch (Control Plane Logs)

| Item                       | Cost                           |
|----------------------------|--------------------------------|
| Log ingestion              | \$0.50/GB ingested             |
| Log storage                | \$0.03/GB-month stored         |
| EKS control plane logs     | ~\$1-5/month depending on traffic |

---

### 8. Data Transfer

Significant costs arise from:

- Pods in one AZ communicating with pods in another AZ (\$0.01/GB)
- Traffic between EKS and RDS across AZs
- Egress to the internet via NAT Gateway

**Cost reduction:** Prefer same-AZ pod-to-pod communication using
topology-aware routing.

---

## Development vs Production Cost Strategy

| Decision                   | Development              | Production               |
|----------------------------|--------------------------|--------------------------|
| NAT Gateways               | 1 (shared)               | 3 (one per AZ)           |
| Node capacity type         | On-Demand only           | On-Demand + Spot mix     |
| Minimum node count         | Low (can scale to 0 at night) | Meets HA requirements  |
| EBS volume size            | Small                    | Production sized         |
| Log retention              | 7 days                   | 30+ days                 |
| Multi-AZ RDS               | Single-AZ                | Multi-AZ enabled         |
| ALB count                  | 1 shared                 | 1 per environment        |

---

## Cost Guardrails

### AWS Billing Alerts

Set up AWS Budgets alerts:

| Threshold    | Action                         |
|--------------|--------------------------------|
| 50% of budget| Email notification             |
| 80% of budget| Email + Slack notification     |
| 100% of budget| Immediate investigation       |

### Cluster cost optimizations

1. **VPC Endpoints** for S3, ECR, STS, EC2 — eliminates NAT Gateway costs for AWS API traffic
2. **ECR lifecycle policies** — delete untagged and old images automatically
3. **Cluster Autoscaler** — scale down nodes when not needed
4. **Spot instances** for application node group in production (60-80% savings)
5. **Resource requests** on all pods — prevents node over-provisioning
6. **Right-size instances** — monitor actual CPU/memory usage vs provisioned

### Development cost control

Stop the dev cluster when not actively using it:

```bash
# Scale down all node groups to 0 (stops EC2 costs, not EKS control plane)
# EKS control plane still costs ~$0.10/hr even with 0 nodes
eksctl scale nodegroup --cluster=<name> --nodes=0 --name=<nodegroup>
```

Note: EKS control plane (\$0.10/hr = ~\$72/month) runs regardless of nodes.
Destroy the entire cluster when doing multi-week breaks.

---

## Cost Monitoring

Implement AWS Cost Explorer tags:

| Tag Key       | Tag Value Examples                      |
|---------------|-----------------------------------------|
| Project       | production-eks-platform-lab             |
| Environment   | dev / staging / production              |
| Team          | platform                                |
| ManagedBy     | terraform                               |

All Terraform-provisioned resources will carry these tags.
Cost breakdown by environment, project, and resource type becomes possible.
