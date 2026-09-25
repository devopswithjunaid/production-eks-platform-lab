# VPC Module

## Purpose

This module creates the complete AWS networking foundation.

## Resources Created

- AWS VPC
- Public Subnets (one per AZ) — for ALB and NAT Gateway
- Private EKS Subnets (one per AZ) — for worker nodes and pods
- Private Data Subnets (one per AZ) — for RDS, ElastiCache
- Internet Gateway
- NAT Gateway (one per environment — dev: 1, prod: 3)
- Route Tables and associations
- Elastic IPs for NAT Gateway
- Subnet tags for EKS and Load Balancer Controller discovery

## Inputs

| Variable              | Description                          |
|-----------------------|--------------------------------------|
| `vpc_cidr`            | VPC CIDR block (e.g. 10.20.0.0/16)  |
| `environment`         | Environment name (dev/staging/prod)  |
| `project`             | Project name for tagging             |
| `availability_zones`  | List of AZs to use                   |
| `public_subnet_cidrs` | CIDRs for public subnets             |
| `private_eks_cidrs`   | CIDRs for private EKS subnets        |
| `private_data_cidrs`  | CIDRs for private data subnets       |
| `single_nat_gateway`  | Use one NAT Gateway (dev: true)      |

## Outputs

| Output                  | Description                          |
|-------------------------|--------------------------------------|
| `vpc_id`                | VPC ID                               |
| `public_subnet_ids`     | List of public subnet IDs            |
| `private_eks_subnet_ids`| List of private EKS subnet IDs       |
| `private_data_subnet_ids`| List of private data subnet IDs     |
| `nat_gateway_ids`       | List of NAT Gateway IDs              |
| `vpc_cidr_block`        | The VPC CIDR block                   |

## Usage

```hcl
module "vpc" {
  source = "../../modules/vpc"

  vpc_cidr           = "10.20.0.0/16"
  environment        = "dev"
  project            = "production-eks-platform-lab"
  availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]
  single_nat_gateway = true
}
```
