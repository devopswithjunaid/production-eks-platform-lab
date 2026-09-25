# EKS Terraform Design

## Cluster Architecture

The `terraform/modules/eks` module provisions the foundational Amazon EKS control plane, worker node compute tiers, IAM execution boundaries, security groups, access entries, and foundational AWS-managed addons.

```text
                    Amazon EKS (module.eks)
                        │
          ┌─────────────┴─────────────────────────────┐
          │                                           │
     AWS Managed                                 Worker Nodes
     Control Plane                             (Private EKS Subnets)
     ├── kube-apiserver                               │
     ├── etcd (KMS Encrypted)            ┌────────────┼────────────┐
     ├── kube-scheduler                  │            │            │
     └── kube-controller-manager   System Nodes   App Nodes   Monitoring Nodes
                                   (Tainted)      (Default)    (Tainted)
```

Platform workloads (Argo CD, HashiCorp Vault, Prometheus, Grafana, Loki, Kyverno, Falco) are intentionally **excluded** from this Terraform module so that Terraform owns only AWS/Kubernetes infrastructure while Argo CD owns platform and application workloads.

---

## Control Plane

AWS operates the EKS control plane across multiple Availability Zones in an AWS-managed VPC and attaches cross-account Elastic Network Interfaces (ENIs) into our `private_eks` subnets (`10.20.16.0/20`, `10.20.32.0/20`, `10.20.48.0/20`).

We do not provision EC2 master nodes or manage etcd clusters directly. Instead, `aws_eks_cluster.this` declares the desired Kubernetes version, networking boundaries, authentication mode (`API`), audit logging, and KMS secret encryption.

---

## Cluster IAM Role

`aws_iam_role.cluster` is assumed exclusively by `eks.amazonaws.com`.

It attaches:
- `arn:aws:iam::aws:policy/AmazonEKSClusterPolicy`
- `arn:aws:iam::aws:policy/AmazonEKSVPCResourceController`

**Why separate from the Node IAM role?**
The control plane needs AWS permissions to manage cluster-level ENIs and security groups in our VPC, whereas EC2 worker nodes need permissions for `kubelet` to register with the cluster and pull container images from ECR. Mixing these roles would violate least privilege and allow a compromised worker node to exercise control-plane IAM privileges.

---

## API Endpoint

- **`endpoint_private_access = true`**: All `kubelet`-to-API-server traffic and internal Pod-to-API traffic stays strictly inside the VPC over AWS PrivateLink ENIs without traversing the internet or NAT Gateway.
- **`endpoint_public_access = true`**: Enabled initially so engineers and CI/CD runners outside the VPC can reach `kube-apiserver`.
- **`public_access_cidrs`**: Restricted via input variable (`var.public_access_cidrs`) to trusted administrative CIDR blocks rather than leaving the API server exposed to `0.0.0.0/0` in production.

---

## Cluster Logging

`aws_cloudwatch_log_group.eks` (`/aws/eks/<cluster-name>/cluster`) is provisioned prior to the cluster with configurable retention (`30` days in dev, `90` days in production), and all five EKS control-plane log streams are enabled:

1. **`api`**: Every API request to `kube-apiserver`
2. **`audit`**: Security audit trail — *who* changed *which* Kubernetes object and *when*
3. **`authenticator`**: AWS IAM-to-Kubernetes RBAC authentication checks and failures
4. **`controllerManager`**: Replication, node lifecycle, and endpoint controller loops
5. **`scheduler`**: Why a Pod was placed on a specific node or why it remained `Pending`

---

## Encryption

`aws_eks_cluster.this` configures envelope encryption (`encryption_config`) for Kubernetes `secrets` using our customer-managed KMS key (`module.kms.eks_key_arn`).

When a Kubernetes `Secret` is created, `kube-apiserver` encrypts the payload with a Data Encryption Key (DEK) wrapped by our customer-managed KMS key before writing to `etcd`. This ensures secrets are encrypted at rest with a key whose rotation, IAM key policy, and CloudTrail audit log we control.

---

## Kubernetes Network Configuration

- **Pod Networking**: Provided by AWS VPC CNI (`aws-node`) allocating VPC IPs from the `/20` Private EKS Subnets (`4,091` usable IPs per AZ).
- **Service IPv4 CIDR**: `172.20.0.0/16` (`kubernetes_network_config.service_ipv4_cidr`), completely non-overlapping with our VPC CIDR (`10.20.0.0/16`).
- **IP Family**: `ipv4`.

---

## Managed Node Groups

We use `aws_eks_node_group` across our three Private EKS Subnets (`us-east-1a`, `us-east-1b`, `us-east-1c`).
Managed Node Groups automate EC2 Launch Templates, Auto Scaling Groups, AMI patching, and graceful node draining (`kubectl cordon` + `kubectl drain`) during rolling upgrades.

Instead of a single monolithic pool, compute is partitioned into three dedicated node groups (`system`, `application`, `monitoring`).

---

## System Node Group

- **Purpose**: Runs cluster-critical controllers (`CoreDNS`, `Metrics Server`, `AWS Load Balancer Controller`, `ExternalDNS`, `Cert Manager`, `Argo CD`).
- **Capacity & Sizing**: `ON_DEMAND`, `t3.medium` (`min = 2`, `desired = 2`, `max = 4`).
- **Labels**: `workload = "system"`, `node-group = "system"`.
- **Taints**: `workload=system:NoSchedule` — prevents application workloads from scheduling onto system nodes and starving `CoreDNS`.

---

## Application Node Group

- **Purpose**: Runs business microservices (`frontend`, `cart-service`, `checkout-service`, `payment-service`, `product-catalog`).
- **Capacity & Sizing**: `ON_DEMAND` initially (`t3.large`, `min = 2`, `desired = 2`, `max = 8`). Spot instances will be evaluated later.
- **Labels**: `workload = "application"`, `node-group = "application"`.
- **Taints**: None (default landing zone for standard application Pods).

---

## Monitoring Node Group

- **Purpose**: Isolates observability infrastructure (`Prometheus`, `Grafana`, `Loki`, `Tempo`, `OpenTelemetry Collector`) so an application traffic spike or memory leak cannot evict or throttle monitoring tools during an incident.
- **Capacity & Sizing**: `ON_DEMAND`, `t3.large` (`min = 1`, `desired = 1`, `max = 3` in dev; `min = 2` in prod).
- **Labels**: `workload = "monitoring"`, `node-group = "monitoring"`.
- **Taints**: `workload=monitoring:NoSchedule` — only observability Pods with the matching toleration can run here.

---

## Node IAM

`aws_iam_role.node` is assumed by `ec2.amazonaws.com` and holds **only** the three AWS-managed policies required by `kubelet` and node networking:
1. `AmazonEKSWorkerNodePolicy`
2. `AmazonEKS_CNI_Policy`
3. `AmazonEC2ContainerRegistryReadOnly`

**Crucial Security Boundary:**
`aws_iam_role.node` receives **zero** permissions to application resources (`S3`, `Secrets Manager`, `RDS`, `DynamoDB`, `Route53`). Application and controller Pods obtain scoped AWS credentials exclusively via **EKS Pod Identity**.

---

## EKS Access Entries

Instead of the legacy, brittle `aws-auth` ConfigMap, the cluster sets `authentication_mode = "API_AND_CONFIG_MAP"` (transitioning to pure `API`) and provisions `aws_eks_access_entry` + `aws_eks_access_policy_association`:

- **PlatformAdmin**: Bound to `AmazonEKSClusterAdminPolicy` (`cluster` scope).
- **Developer**: Bound to `AmazonEKSEditPolicy` (restricted to the `dev` namespace scope — never `cluster-admin`).
- **ReadOnly**: Bound to `AmazonEKSViewPolicy` (`cluster` scope).

---

## EKS Addons

The module manages the five foundational AWS-native EKS addons via `aws_eks_addon`:

1. **`vpc-cni`**: Allocates VPC ENIs and secondary IPs/prefixes to Pods.
2. **`eks-pod-identity-agent`**: Node DaemonSet that brokers temporary AWS IAM credentials for Pods using `pods.eks.amazonaws.com`.
3. **`coredns`**: Internal cluster DNS (`*.svc.cluster.local`).
4. **`kube-proxy`**: Maintains `iptables`/`IPVS` rules for `ClusterIP` Services.
5. **`aws-ebs-csi-driver`**: Provisions GP3 EBS persistent volumes for stateful workloads (authenticated via EKS Pod Identity).

---

## Pod Identity

With `eks-pod-identity-agent` installed as an addon, any Kubernetes `ServiceAccount` can be mapped to a dedicated AWS IAM Role using `aws_eks_pod_identity_association`.

The module demonstrates this immediately by binding `kube-system/ebs-csi-controller-sa` to `aws_iam_role.ebs_csi` (which trusts `pods.eks.amazonaws.com`) so the EBS CSI Driver can attach EBS volumes without granting EBS permissions to the underlying EC2 worker node IAM role.

---

## Security Groups

The module creates two explicit security groups with least-privilege rules:

1. **Cluster Security Group (`aws_security_group.cluster`)**:
   - Allows inbound TCP `443` from the **Node Security Group** (`kubelet` → `kube-apiserver`).
   - Allows outbound traffic to the **Node Security Group** (`10250` for `kubelet` exec/logs and `443` for admission webhooks).
2. **Node Security Group (`aws_security_group.node`)**:
   - Allows all node-to-node communication within the cluster (`self = true`) for Pod-to-Pod and CoreDNS traffic.
   - Allows inbound TCP `443` and `10250–65535` from the **Cluster Security Group**.
   - Allows outbound egress (`0.0.0.0/0`) so nodes can pull container images and reach AWS APIs via the NAT Gateway.

---

## Upgrade Strategy

Kubernetes versions (`var.cluster_version`) and addon versions follow a strict promotion path:
`dev` → `staging` → `production`.

1. Update `kubernetes_version` in `dev` and run `terraform plan`.
2. Control plane upgrades in-place via AWS EKS.
3. Managed Node Groups perform rolling node replacement (launching new AMI nodes, cordoning and draining existing nodes while respecting `PodDisruptionBudgets`).

---

## Scaling Strategy

- **Horizontal Pod Autoscaler (HPA)** scales Pod replicas inside existing node capacity.
- **Managed Node Group Auto Scaling** (and later **Karpenter**) scales EC2 worker nodes between `min_size` and `max_size` across the three Availability Zones.
- Karpenter is intentionally deferred until after our base Managed Node Groups and HPA behavior are validated in action.

---

## Failure Scenarios

1. **Worker Node Termination (`EC2 Failure`)**:
   - Managed Node Group Auto Scaling Group detects the unhealthy EC2 instance, launches a replacement node in the Private EKS Subnet, and `kube-scheduler` reschedules evicted Pods onto surviving nodes.
2. **Single Availability Zone Outage**:
   - Because each node group spans all three Private EKS Subnets (`us-east-1a`, `us-east-1b`, `us-east-1c`), `66%` of node capacity remains online and AWS's multi-AZ control plane automatically routes API traffic through the surviving AZs.
3. **VPC Subnet IP Exhaustion**:
   - Even if EC2 CPU/Memory capacity is available, `vpc-cni` will fail to allocate secondary IPs (`FailedCreatePodSandBox`), leaving Pods in `Pending`/`ContainerCreating`. Our `/20` Private EKS Subnets (`4,091` usable IPs per AZ) and VPC CNI monitoring guard against this scenario.
