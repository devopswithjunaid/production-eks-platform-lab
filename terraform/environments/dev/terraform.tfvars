# Environment: Development
# Values for all declared variables

# ─── Global ───────────────────────────────────────────────────────────────────
environment = "dev"
aws_region  = "us-east-1"
project     = "production-eks-platform-lab"

# ─── VPC ──────────────────────────────────────────────────────────────────────
vpc_cidr           = "10.20.0.0/16"
availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]

public_subnet_cidrs = [
  "10.20.0.0/24",
  "10.20.1.0/24",
  "10.20.2.0/24"
]

private_eks_subnet_cidrs = [
  "10.20.16.0/20",
  "10.20.32.0/20",
  "10.20.48.0/20"
]

private_data_subnet_cidrs = [
  "10.20.64.0/24",
  "10.20.65.0/24",
  "10.20.66.0/24"
]

single_nat_gateway = true

# ─── EKS Control Plane & API Endpoint ─────────────────────────────────────────
cluster_name            = "production-eks-dev"
kubernetes_version      = "1.31"
endpoint_private_access = true
endpoint_public_access  = true

# Restricted administrative CIDR list (replace with admin public IP/32 before apply)
public_access_cidrs = [
  "139.135.32.172/32"
]

service_ipv4_cidr = "172.20.0.0/16"

enabled_cluster_log_types = [
  "api",
  "audit",
  "authenticator",
  "controllerManager",
  "scheduler"
]

# ─── EKS Managed Node Groups (System, Application, Monitoring) ────────────────
node_groups = {
  system = {
    instance_types = ["t3.medium"]
    capacity_type  = "ON_DEMAND"
    disk_size      = 20
    min_size       = 2
    desired_size   = 2
    max_size       = 4
    labels = {
      "workload"   = "system"
      "node-group" = "system"
    }
    taints = [
      {
        key    = "workload"
        value  = "system"
        effect = "NO_SCHEDULE"
      }
    ]
  }

  application = {
    instance_types = ["t3.large"]
    capacity_type  = "ON_DEMAND"
    disk_size      = 20
    min_size       = 2
    desired_size   = 2
    max_size       = 8
    labels = {
      "workload"   = "application"
      "node-group" = "application"
    }
    taints = []
  }

  monitoring = {
    instance_types = ["t3.large"]
    capacity_type  = "ON_DEMAND"
    disk_size      = 50
    min_size       = 1
    desired_size   = 1
    max_size       = 3
    labels = {
      "workload"   = "monitoring"
      "node-group" = "monitoring"
    }
    taints = [
      {
        key    = "workload"
        value  = "monitoring"
        effect = "NO_SCHEDULE"
      }
    ]
  }
}

# ─── GitHub OIDC ──────────────────────────────────────────────────────────────
github_org  = "devopswithjunaid"
github_repo = "production-eks-platform-lab"

# ─── ECR ──────────────────────────────────────────────────────────────────────
ecr_repositories = [
  "frontend",
  "checkout-service",
  "payment-service",
  "cart-service",
  "product-catalog"
]
