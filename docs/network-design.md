# AWS Network Design

## VPC

CIDR:

```
10.20.0.0/16
```

The VPC provides sufficient IP space for Kubernetes nodes,
Pods, load balancers, AWS endpoints, and future expansion.

---

## Availability Zones

The platform will span three Availability Zones.

- AZ-A
- AZ-B
- AZ-C

Actual AWS AZ names will be selected dynamically by Terraform.

---

## Public Subnets

| AZ    | CIDR           |
|-------|----------------|
| AZ-A  | 10.20.0.0/24   |
| AZ-B  | 10.20.1.0/24   |
| AZ-C  | 10.20.2.0/24   |

Public subnets will contain internet-facing infrastructure such as:

- Application Load Balancers
- NAT Gateways

They will have routes to the Internet Gateway.

Required subnet tag for AWS Load Balancer Controller discovery:

```
kubernetes.io/role/elb = 1
```

---

## Private EKS Subnets

| AZ    | CIDR             |
|-------|------------------|
| AZ-A  | 10.20.16.0/20    |
| AZ-B  | 10.20.32.0/20    |
| AZ-C  | 10.20.48.0/20    |

EKS worker nodes will run only inside private subnets.

Kubernetes Pods will also consume VPC IP addresses through the
AWS VPC CNI.

Worker nodes will not receive public IPv4 addresses.

These subnets are deliberately much larger than the public subnets
because the AWS VPC CNI allocates VPC IP addresses directly to
Kubernetes Pods. A single node can consume many IP addresses
depending on instance type and workload density.

Required subnet tag for AWS Load Balancer Controller discovery
(internal load balancers):

```
kubernetes.io/role/internal-elb = 1
```

---

## Private Data Subnets

| AZ    | CIDR             |
|-------|------------------|
| AZ-A  | 10.20.64.0/24    |
| AZ-B  | 10.20.65.0/24    |
| AZ-C  | 10.20.66.0/24    |

Data subnets will not have direct routes to the Internet Gateway.

Future managed data services can be placed here, including:

- Amazon RDS
- ElastiCache
- Other internal data services

---

## Subnet Architecture Summary

```
AWS Region
│
└── VPC  10.20.0.0/16
    │
    ├── Availability Zone A
    │   ├── Public Subnet         10.20.0.0/24
    │   ├── Private EKS Subnet    10.20.16.0/20
    │   └── Private Data Subnet   10.20.64.0/24
    │
    ├── Availability Zone B
    │   ├── Public Subnet         10.20.1.0/24
    │   ├── Private EKS Subnet    10.20.32.0/20
    │   └── Private Data Subnet   10.20.65.0/24
    │
    └── Availability Zone C
        ├── Public Subnet         10.20.2.0/24
        ├── Private EKS Subnet    10.20.48.0/20
        └── Private Data Subnet   10.20.66.0/24
```

---

## NAT Gateway Architecture

### Internet egress path for private workloads

```
Pod
 ↓
Node (Private EKS Subnet)
 ↓
Private Route Table
 ↓
NAT Gateway (Public Subnet)
 ↓
Internet Gateway
 ↓
Internet
```

### Development vs Production trade-off

| Environment | NAT Strategy              | Reason                          |
|-------------|---------------------------|---------------------------------|
| Development | 1 NAT Gateway (shared)    | Cost optimized                  |
| Production  | 1 NAT Gateway per AZ      | AZ-level egress failure isolation |

In production, if AZ-A's NAT Gateway fails, workloads in AZ-B and
AZ-C retain independent internet egress. In development this cost
is not justified.

---

## Load Balancer Traffic Flow

```
User
 │
 ▼
Internet
 │
 ▼
Route 53
 │
 ▼
Application Load Balancer  (Public Subnets)
 │
 ▼
AWS Load Balancer Controller
 │
 ▼
Kubernetes Service
 │
 ▼
Frontend Pod  (Private EKS Subnet)
 │
 ▼
Other Microservices
```

Inbound traffic does NOT travel through NAT Gateway.
NAT Gateway handles only outbound (egress) traffic from private resources.
Inbound internet traffic enters through the Internet Gateway directly to
the ALB in the public subnet.

---

## EKS API Endpoint Configuration

### Initial configuration

```
EKS API Endpoint
├── Private access: ENABLED
└── Public access:  ENABLED
```

Public access will eventually be restricted to trusted administrator CIDRs.

### Why public + private instead of public-only?

With public + private endpoint mode:

- Node-to-control-plane traffic stays within the VPC (private endpoint)
- Administrators can still reach the API externally (public endpoint)
- AWS recommends this as the default production-ready starting point

### Future target

```
Private-only EKS API
```

Access via VPN, bastion host, or AWS Systems Manager Session Manager.
This eliminates all public API exposure but requires an administrative
access path into the VPC.

---

## Why Three Separate Subnet Types

### Public subnet

Has a route:

```
0.0.0.0/0 → Internet Gateway
```

Resources here can receive and initiate internet traffic directly.
Used for: ALBs, NAT Gateways.

### Private EKS subnet

No direct internet route. Egress only via NAT Gateway.

```
Private Subnet
│
├── EKS Node
│    ├── Pod (VPC IP)
│    ├── Pod (VPC IP)
│    └── Pod (VPC IP)
│
└── No public IPv4 assigned
```

Worker nodes here cannot be reached from the internet directly,
which is the AWS-recommended security posture for Kubernetes workloads.

### Private data subnet

No internet route at all (no NAT route required for data services).

```
Application Pod  →  RDS (private traffic only)
Internet         →  X  (no route to RDS)
```

Isolates stateful data services from both internet and application compute
layers at the network level.
