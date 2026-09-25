# VPC Design

## VPC CIDR

The VPC uses the primary IPv4 CIDR block `10.20.0.0/16`, providing **65,536** total IPv4 addresses.

DNS resolution (`enable_dns_support`) and DNS hostnames (`enable_dns_hostnames`) are enabled at the VPC level so that Amazon EKS worker nodes, internal AWS endpoints, and Route 53 private DNS resolution work seamlessly.

---

## Availability Zones

The network spans **three Availability Zones** (`AZ-A`, `AZ-B`, `AZ-C`) within the region.

Even though Amazon EKS requires a minimum of two Availability Zones for control-plane ENIs, provisioning three Availability Zones ensures:

- True quorum distribution for stateful workloads (etcd, Vault, distributed caches)
- Higher resilience if an entire Availability Zone suffers an outage (`66%` remaining capacity instead of `50%`)
- Production-realistic failure-domain testing

---

## Public Subnets

| Availability Zone | Subnet CIDR | Total IPs | Usable IPs (AWS reserves 5) |
|---|---|---|---|
| AZ-A | `10.20.0.0/24` | 256 | 251 |
| AZ-B | `10.20.1.0/24` | 256 | 251 |
| AZ-C | `10.20.2.0/24` | 256 | 251 |

**Purpose:**
Public subnets host only internet-facing network infrastructure:
- Internet-facing Application Load Balancers (ALBs)
- NAT Gateways

No Kubernetes worker nodes or application databases are ever placed in public subnets.
Public subnets are tagged with `kubernetes.io/role/elb = 1` so the AWS Load Balancer Controller can automatically discover them when provisioning internet-facing load balancers.

---

## Private EKS Subnets

| Availability Zone | Subnet CIDR | Total IPs | Usable IPs (AWS reserves 5) |
|---|---|---|---|
| AZ-A | `10.20.16.0/20` | 4,096 | 4,091 |
| AZ-B | `10.20.32.0/20` | 4,096 | 4,091 |
| AZ-C | `10.20.48.0/20` | 4,096 | 4,091 |

**Purpose:**
All Amazon EKS worker nodes and Kubernetes Pods run inside these subnets.
Worker nodes do not receive public IPv4 addresses (`map_public_ip_on_launch = false`).
Private EKS subnets are tagged with `kubernetes.io/role/internal-elb = 1` so the AWS Load Balancer Controller can automatically place internal load balancers in these subnets.

---

## Private Data Subnets

| Availability Zone | Subnet CIDR | Total IPs | Usable IPs (AWS reserves 5) |
|---|---|---|---|
| AZ-A | `10.20.64.0/24` | 256 | 251 |
| AZ-B | `10.20.65.0/24` | 256 | 251 |
| AZ-C | `10.20.66.0/24` | 256 | 251 |

**Purpose:**
Dedicated, isolated subnets for stateful managed data services such as Amazon RDS (PostgreSQL) and Amazon ElastiCache (Redis).
These subnets have **no route to the Internet Gateway or NAT Gateway** — traffic is strictly internal to the VPC.

---

## Internet Gateway

One Internet Gateway (`IGW`) is attached to the VPC.
It provides two functions:
1. Inbound and outbound internet path for resources in the **Public Subnets** (internet-facing ALBs)
2. Outbound internet termination point for traffic translated by the **NAT Gateway(s)**

---

## NAT Gateway

Worker nodes and Pods in the Private EKS Subnets need outbound internet connectivity (to pull container images from external registries, reach public APIs, and download OS security updates) without being reachable from the internet.

- **Development Environment (`single_nat_gateway = true`)**: Deploys **1 NAT Gateway** in Public Subnet A (`AZ-A`) shared by all three Private EKS Subnets to minimize hourly fixed costs.
- **Production Environment (`single_nat_gateway = false`)**: Deploys **3 NAT Gateways** (one in each Availability Zone's Public Subnet) so each Private EKS Subnet routes through its local AZ's NAT Gateway, eliminating cross-AZ data transfer charges and single-AZ failure blast radius.

Each NAT Gateway requires a dedicated static **Elastic IP (`EIP`)**.

---

## Route Tables

1. **Public Route Table (`1`)**
   - `10.20.0.0/16` → `local`
   - `0.0.0.0/0` → `Internet Gateway`
   - Associated with Public Subnets A, B, and C.

2. **Private EKS Route Table(s) (`1` in dev, `3` in prod)**
   - `10.20.0.0/16` → `local`
   - `0.0.0.0/0` → `NAT Gateway` (AZ-local NAT in prod, shared NAT-A in dev)
   - Associated with Private EKS Subnets A, B, and C.

3. **Private Data Route Table (`1`)**
   - `10.20.0.0/16` → `local`
   - *No `0.0.0.0/0` route* — completely air-gapped from the internet.
   - Associated with Private Data Subnets A, B, and C.

---

## Network Flow

```
INTERNET
   │
   ▼
Internet Gateway
   │
   ├─────────────────────────────────────────┐
   ▼                                         ▼
Public Subnet (ALB)                  Public Subnet (NAT Gateway)
   │                                         ▲
   │ Inbound HTTP/HTTPS                      │ Outbound Egress (0.0.0.0/0)
   ▼                                         │
Private EKS Subnet (Worker Nodes & Pods) ────┘
   │
   │ Internal VPC Traffic (TCP 5432 / 6379)
   ▼
Private Data Subnet (RDS / ElastiCache — No Internet Route)
```

---

## IP Address Planning

In Amazon EKS, the **AWS VPC CNI** plugin allocates VPC IP addresses to Pods.
However, IP consumption is not just `1 Pod = 1 IP`:
- Each EC2 worker node attaches multiple **Elastic Network Interfaces (ENIs)** and pre-allocates a **warm pool** of secondary IPv4 addresses (or `/28` IPv4 prefixes when **Prefix Delegation** is enabled) so new Pods can start rapidly without waiting for EC2 API calls.
- Pod density per node is constrained by both the **instance type's maximum ENIs × IPs per ENI** and the **subnet's available IP pool**.
- Sizing each Private EKS Subnet as a `/20` (`4,091` usable IPs per AZ, `12,273` usable IPs across the 3 AZs) prevents subnet IP exhaustion during rolling node upgrades, HPA scale-outs, and warm-pool pre-allocation, while leaving over `45,000` unallocated IPs in `10.20.0.0/16` for future expansion.

---

## Security Considerations

- **No Public IPs on Compute**: Worker nodes and Pods run strictly in private subnets with `map_public_ip_on_launch = false`.
- **Three-Tier Network Segmentation**: Public ingress, private Kubernetes compute, and private data storage reside in separate CIDR ranges, making Security Group and Network ACL rules simple and auditable.
- **Air-Gapped Data Tier**: Private Data Subnets lack any `0.0.0.0/0` route, ensuring database instances cannot initiate or receive internet connections even if a Security Group is misconfigured.

---

## Cost Considerations

- **NAT Gateway Fixed + Data Processing Costs**: Each NAT Gateway costs ~\$0.045/hour (~\$32.40/month) plus \$0.045 per GB processed. Using `single_nat_gateway = true` in development saves ~\$65/month.
- **Cross-AZ Data Transfer**: In development, Pods in `AZ-B` and `AZ-C` routing through `NAT-A` incur cross-AZ data transfer fees for internet egress. In production, per-AZ NAT Gateways keep egress traffic within the same AZ.
- **Future Optimization (VPC Endpoints)**: Gateway VPC Endpoints (`S3`) and Interface VPC Endpoints (`ECR`, `STS`, `CloudWatch Logs`) can keep high-volume AWS traffic off the NAT Gateway entirely.

---

## Failure Scenarios

1. **Single NAT Gateway Failure (Development)**
   - **Impact**: Pods in all three AZs lose outbound internet access (cannot pull public images or reach external APIs). Inbound user traffic via the ALB to already-running Pods continues working because inbound traffic uses the Internet Gateway, not the NAT Gateway.
   - **Mitigation in Production**: Deploy one NAT Gateway per AZ (`single_nat_gateway = false`).

2. **Availability Zone Outage**
   - **Impact**: Nodes and Pods in the failed AZ become unreachable.
   - **Mitigation**: ALB stops routing to the unhealthy AZ; Kubernetes reschedules evicted Pods onto Private EKS Subnets in the two healthy AZs.

3. **EKS Subnet IP Exhaustion**
   - **Impact**: New Pods stay in `ContainerCreating` (`failed to assign an IP address to container`) and new worker nodes fail to join the cluster.
   - **Mitigation**: `/20` subnets provide 4,091 IPs per AZ, and VPC CNI prefix delegation (`/28` prefixes) can be enabled if node/Pod density grows further.
