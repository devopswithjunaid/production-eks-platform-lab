# Disaster Recovery Design

## Purpose

Senior engineers design for failure before it happens.
This document defines every significant failure scenario,
how it is detected, what impact it has, how we recover,
and how we prevent recurrence.

---

## Failure Scenarios

---

### 1. Pod Failure

**What happens:**
A container crashes, OOMKills, or fails its liveness probe.

```
Detection:
  Prometheus: kube_pod_container_status_restarts_total increases
  Alertmanager: Pod crash loop alert fires
  kubectl: pod shows CrashLoopBackOff or OOMKilled

Impact:
  Single pod: traffic routed to other healthy replicas (Service load balances)
  All pods: service unavailable

Recovery:
  Kubernetes restarts pod automatically (exponential backoff)
  If OOMKill: increase memory limits or fix memory leak
  If crash: investigate logs via Loki, fix application bug

Prevention:
  Define memory limits correctly
  Add liveness + readiness probes
  Run minimum 2 replicas (PodDisruptionBudget)
  Load test to find memory ceiling before production
```

---

### 2. Node Failure

**What happens:**
An EC2 node terminates unexpectedly or becomes unresponsive.

```
Detection:
  Kubernetes: node status changes to NotReady
  Prometheus: node down alert
  AWS: EC2 instance health check fails

Impact:
  Pods on that node evicted and rescheduled to healthy nodes
  Temporary disruption if not enough capacity elsewhere
  Cluster Autoscaler provisions replacement node

Recovery:
  Kubernetes reschedules pods automatically (within ~2-5 minutes)
  Cluster Autoscaler replaces the terminated node
  Multi-AZ placement ensures workloads continue on other AZs

Prevention:
  Run pods across multiple AZs
  Define PodDisruptionBudgets
  Use minimum 2 replicas per service
  Managed node groups handle EC2 replacement automatically
```

---

### 3. Availability Zone Failure

**What happens:**
An entire AWS AZ becomes unavailable.

```
Detection:
  AWS Service Health Dashboard
  Prometheus: multiple nodes NotReady in same AZ
  Alertmanager: multiple pod failure alerts from same zone

Impact:
  All pods on nodes in that AZ are evicted
  Traffic shifts to pods in remaining AZs
  NAT Gateway in that AZ is unavailable (dev: shared NAT = total egress loss)
  ALB routes traffic only to healthy AZ targets

Recovery:
  Kubernetes reschedules pods to AZ-B and AZ-C nodes
  Cluster Autoscaler adds nodes in healthy AZs if needed
  ALB health checks remove unhealthy targets automatically

Prevention:
  Multi-AZ node groups (nodes in AZ-A, AZ-B, AZ-C)
  Pod topology spread constraints across AZs
  Production: 1 NAT Gateway per AZ (eliminates shared egress dependency)
  Test AZ failure in dev by draining all nodes in one AZ
```

---

### 4. Database Failure (RDS)

**What happens:**
Amazon RDS primary instance fails or becomes unreachable.

```
Detection:
  Application logs: connection errors (Loki alert)
  Prometheus: db_query_duration_seconds spike or no data
  Alertmanager: HTTP 5xx error rate increase on affected services

Impact:
  All services that depend on RDS cannot serve write requests
  If RDS Multi-AZ enabled: automatic failover in 60-120 seconds
  If no Multi-AZ: manual recovery required

Recovery:
  Multi-AZ RDS: automatic failover to standby
  Services reconnect automatically (with retry logic)
  No data loss (synchronous standby replication)

Prevention:
  Enable RDS Multi-AZ in production
  Implement retry + circuit breaker logic in services
  Test database failover in dev (force-failover via RDS console)
  Monitor DB connection pool exhaustion
```

---

### 5. Bad Deployment (Failed Rollout)

**What happens:**
A new version is deployed with a bug or misconfiguration.

```
Detection:
  Argo CD: rollout shows Degraded status
  Prometheus: HTTP 5xx error rate increase
  Prometheus: Pod restart count increases
  Loki: application errors in logs
  Kubernetes: readiness probe fails → pods never become Ready

Impact:
  Old pods remain serving traffic (readiness probe prevents bad pod traffic)
  If all pods crash: service unavailable

Recovery:
  Option 1 (GitOps): revert commit in GitOps repo → Argo CD deploys previous version
  Option 2 (Emergency): kubectl rollout undo deployment/<name>
  Then: sync GitOps repo to match cluster state

Prevention:
  Staging environment validation before production
  Readiness probes catch broken pods before they receive traffic
  Argo Rollouts for canary/blue-green with automatic rollback on errors
  Progressive delivery: deploy to 10% traffic → validate → 100%
```

---

### 6. Secret Failure (Missing or Rotated)

**What happens:**
A Kubernetes Secret is deleted, modified, or Vault becomes unavailable.

```
Detection:
  Application logs: authentication errors, connection refused
  Pod status: CrashLoopBackOff (if secret mounted as volume)
  Loki: secret-related errors in application logs

Impact:
  Service cannot start or cannot authenticate to dependencies
  Existing running pods may continue (secret was already loaded)
  New pods fail to start

Recovery:
  Restore Kubernetes Secret from backup or recreate
  If Vault: restore Vault from snapshot, or use Vault recovery keys
  Restart affected pods after secret is restored

Prevention:
  Never manually edit secrets in production
  Back up Vault snapshots regularly
  Use Kubernetes Secret versioning patterns
  Monitor secret access patterns in Vault audit logs
```

---

### 7. Terraform Mistake (Infrastructure Damage)

**What happens:**
A Terraform change destroys or modifies critical infrastructure.

```
Detection:
  terraform plan output shows destroy (should be reviewed before apply)
  AWS CloudTrail: unexpected resource deletion events
  Alertmanager: infrastructure-level alerts (node gone, subnet deleted)

Impact:
  Depends on what was destroyed
  NAT Gateway deletion: all pod egress broken
  Subnet deletion: cannot provision new nodes
  EKS cluster deletion: complete platform loss

Recovery:
  Terraform state rollback (restore .tfstate from S3 versioning)
  Re-apply Terraform to recreate resources
  Restore from RDS snapshot if database was affected

Prevention:
  Always run terraform plan before apply
  Require PR review for all Terraform changes
  Enable deletion protection on: RDS, EKS, critical IAM roles
  Use S3 versioning on Terraform state bucket
  Use lifecycle { prevent_destroy = true } on critical resources
  Enable AWS CloudTrail for all API activity
```

---

### 8. GitOps Mistake (Argo CD Sync Corruption)

**What happens:**
Wrong Kubernetes manifests committed to GitOps repo.
Argo CD syncs and applies incorrect desired state.

```
Detection:
  Argo CD dashboard: application shows OutOfSync or Degraded
  Prometheus: pod count drops, error rate rises
  Loki: unexpected service errors

Impact:
  Depends on what was committed
  Wrong image tag: pods crash or serve wrong version
  Deleted Service manifest: traffic breaks
  Wrong resource limits: pods OOMKill

Recovery:
  git revert <bad-commit> in GitOps repo
  Argo CD auto-syncs to reverted state
  Verify application health after sync

Prevention:
  Protect main branch (require PR + review)
  Run manifest validation in CI (kubeval, kustomize build)
  Argo CD sync waves: deploy non-critical first, validate, then critical
  Argo CD auto-sync with prune=false (do not delete resources automatically)
```

---

## Failure Testing Schedule

| Scenario          | Test Method                              | Frequency    |
|-------------------|------------------------------------------|--------------|
| Pod failure       | kubectl delete pod                       | Monthly      |
| Node failure      | kubectl drain node                       | Quarterly    |
| AZ failure        | kubectl cordon all nodes in one AZ       | Quarterly    |
| Bad deployment    | Deploy intentionally broken image        | Every sprint |
| Secret failure    | Delete a secret, observe recovery        | Monthly      |
| Rollback          | Practice GitOps revert procedure         | Monthly      |
| High load         | Load test with k6                        | Monthly      |
| OOMKill           | Deploy pod with insufficient memory limit| Monthly      |

---

## Recovery Time Objectives

| Scenario         | Target RTO (Dev) | Target RTO (Prod) |
|------------------|------------------|-------------------|
| Pod failure      | < 2 minutes      | < 30 seconds      |
| Node failure     | < 5 minutes      | < 3 minutes       |
| AZ failure       | < 10 minutes     | < 5 minutes       |
| Bad deployment   | < 5 minutes      | < 3 minutes       |
| Database failover| < 3 minutes      | < 2 minutes       |
