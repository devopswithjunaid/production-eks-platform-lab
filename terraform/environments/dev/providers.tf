# Provider Configuration
#
# WHY MULTIPLE PROVIDERS?
# -----------------------
# aws        - creates all AWS resources
# kubernetes - manages Kubernetes cluster-level objects (after EKS exists)
# helm       - installs Helm charts (Argo CD bootstrap)
#
# NOTE: kubernetes and helm providers depend on EKS being created first.
# Terraform handles this via depends_on and provider configuration
# that references EKS module outputs.

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

# Primary AWS provider
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Repository  = "devopswithjunaid/production-eks-platform-lab"
    }
  }
}
