# EKS Module

## Purpose

This module creates the Amazon EKS cluster and managed node groups.

## Resources Created

- EKS Cluster
- EKS Cluster IAM Role
- Cluster Security Group
- EKS Managed Node Groups (system, application, monitoring)
- Node Group IAM Role
- EKS Managed Add-ons (VPC CNI, CoreDNS, kube-proxy, EBS CSI Driver)
- EKS Access Entries for authentication

## Inputs

| Variable                  | Description                               |
|---------------------------|-------------------------------------------|
| `cluster_name`            | EKS cluster name                          |
| `kubernetes_version`      | Kubernetes version                        |
| `vpc_id`                  | VPC ID from VPC module                    |
| `private_subnet_ids`      | Private EKS subnet IDs from VPC module    |
| `environment`             | Environment name                          |
| `project`                 | Project name for tagging                  |
| `system_node_config`      | System node group configuration object    |
| `application_node_config` | Application node group config object      |
| `monitoring_node_config`  | Monitoring node group config object       |
| `cluster_admin_arns`      | IAM ARNs for cluster admin access         |

## Outputs

| Output                       | Description                          |
|------------------------------|--------------------------------------|
| `cluster_name`               | EKS cluster name                     |
| `cluster_endpoint`           | EKS API server endpoint              |
| `cluster_ca_certificate`     | Cluster CA certificate               |
| `cluster_security_group_id`  | Cluster security group ID            |
| `node_security_group_id`     | Node security group ID               |
| `cluster_oidc_issuer_url`    | OIDC issuer URL for Pod Identity     |

## Usage

```hcl
module "eks" {
  source = "../../modules/eks"

  cluster_name       = "production-eks-dev"
  kubernetes_version = "1.31"
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_eks_subnet_ids
  environment        = "dev"
  project            = "production-eks-platform-lab"
}
```
