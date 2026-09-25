# Traffic Flow

## Purpose

This document describes how network traffic moves through the platform
for every traffic pattern — external user traffic, inter-service traffic,
database traffic, and egress traffic.

---

## External User Traffic (Inbound)

```
User Browser / Mobile App
           │
           │  HTTPS (port 443)
           ▼
     AWS Route 53
     (DNS resolves app.example.com → ALB DNS name)
           │
           ▼
Application Load Balancer
(Public Subnet — AZ-A, AZ-B, AZ-C)
     │
     │  TLS terminated at ALB
     │  HTTP forwarded to target
     │
     ▼
AWS Load Balancer Controller
(Reads Kubernetes Ingress resource)
     │
     ▼
Kubernetes Ingress
(Routes by Host and Path)
     │
     ├── /          → Frontend Service
     ├── /api/cart  → Cart Service
     └── /api/checkout → Checkout Service
     │
     ▼
Kubernetes Service (ClusterIP)
     │
     ▼
Pod (Private EKS Subnet)
```

### Key points

- Inbound traffic enters via Internet Gateway → ALB → Pod
- NAT Gateway plays NO role in inbound traffic
- TLS terminates at the ALB — pods receive plain HTTP internally
- Pods have no public IP addresses

---

## Internal Service-to-Service Traffic

```
Frontend Pod
     │
     │  HTTP to: http://checkout-service.dev.svc.cluster.local:8080
     ▼
CoreDNS
(Resolves checkout-service → ClusterIP)
     │
     ▼
kube-proxy
(iptables rule maps ClusterIP → Pod IP)
     │
     ▼
Checkout Service Pod
     │
     │  HTTP to: http://payment-service.dev.svc.cluster.local:8080
     ▼
Payment Service Pod
```

### DNS Resolution

Every Kubernetes Service gets a DNS name automatically:

```
<service-name>.<namespace>.svc.cluster.local
```

Examples:

| Service          | DNS Name                                          |
|------------------|---------------------------------------------------|
| frontend         | frontend.dev.svc.cluster.local                    |
| checkout-service | checkout-service.dev.svc.cluster.local            |
| payment-service  | payment-service.dev.svc.cluster.local             |

Services communicate by DNS name — never by Pod IP directly.
Pod IPs are ephemeral and change on restart.

---

## Database Traffic

```
Application Pod (Private EKS Subnet)
     │
     │  TCP 5432 (PostgreSQL)
     │  to: db.cluster.xxxx.us-east-1.rds.amazonaws.com
     ▼
Security Group: allow-eks-to-rds
     │
     ▼
Amazon RDS (Private Data Subnet)
```

```
Application Pod (Private EKS Subnet)
     │
     │  TCP 6379 (Redis)
     │  to: cache.cluster.xxxx.cfg.us-east-1.amazonaws.com
     ▼
Security Group: allow-eks-to-cache
     │
     ▼
ElastiCache Redis (Private Data Subnet)
```

### Key points

- Database subnets have NO route to the internet
- Only pods in EKS subnets can reach the database (Security Group rule)
- Credentials come from Kubernetes Secrets (later Vault)
- Database traffic stays entirely within the VPC

---

## Pod Egress Traffic (Outbound Internet)

```
Pod needs to pull from external API / download package
     │
     ▼
Pod IP (Private EKS Subnet)
     │
     ▼
Node's private route table
     │
     0.0.0.0/0 → NAT Gateway
     ▼
NAT Gateway (Public Subnet)
     │
     0.0.0.0/0 → Internet Gateway
     ▼
Internet Gateway
     │
     ▼
Internet
```

### Key points

- Pod's private IP is translated (NAT) to the NAT Gateway's public Elastic IP
- External servers see the NAT Gateway's Elastic IP — not the Pod's IP
- No inbound connection can be initiated FROM the internet through NAT

---

## Security Controls on Traffic

### Security Groups (AWS Layer)

| Security Group         | Allows                                     |
|------------------------|--------------------------------------------|
| alb-sg                 | 0.0.0.0/0 → 443, 80 (inbound from internet)|
| eks-node-sg            | ALB → 80/443 (inbound from ALB only)       |
| eks-node-sg            | Node-to-node (cluster networking)          |
| rds-sg                 | eks-node-sg → 5432 (RDS from EKS nodes)   |
| cache-sg               | eks-node-sg → 6379 (Redis from EKS nodes) |

### Kubernetes NetworkPolicies (Kubernetes Layer)

Default deny all inter-namespace traffic.
Explicit allow rules per service:

```
Example: payment-service NetworkPolicy

Allow ingress:
  From: checkout-service (same namespace)
  On port: 8080

Deny:
  All other ingress sources
```

### Two layers of network security

Traffic must pass BOTH:
1. AWS Security Group (IP + port filter at the VPC/ENI level)
2. Kubernetes NetworkPolicy (pod-level L3/L4 policy)

This is defence in depth at the network layer.

---

## DNS Flow Detail

```
Pod wants: checkout-service.dev.svc.cluster.local
     │
     ▼
Pod sends DNS query to: 172.20.0.10 (CoreDNS ClusterIP)
     │
     ▼
CoreDNS looks up service in etcd
     │
     ▼
Returns ClusterIP: 172.20.14.25
     │
     ▼
Pod sends TCP to: 172.20.14.25:8080
     │
     ▼
kube-proxy iptables rule on node:
  DNAT 172.20.14.25:8080 → 10.20.16.45:8080 (actual Pod IP)
     │
     ▼
Traffic reaches Pod
```

---

## Load Balancer Subnet Discovery

AWS Load Balancer Controller discovers subnets using tags:

| Subnet Type           | Required Tag                          |
|-----------------------|---------------------------------------|
| Public (internet ALB) | `kubernetes.io/role/elb = 1`          |
| Private (internal ALB)| `kubernetes.io/role/internal-elb = 1` |

These tags will be applied by Terraform when subnets are created.
