variable "cluster_name" {
  description = "Name of the Amazon EKS cluster"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes minor version for the EKS control plane"
  type        = string
  default     = "1.31"
}

variable "environment" {
  description = "Deployment environment (dev / staging / production)"
  type        = string
}

variable "project" {
  description = "Project name used for resource naming and tagging"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the EKS cluster and worker nodes are deployed"
  type        = string
}

variable "subnet_ids" {
  description = "List of Private EKS Subnet IDs across Availability Zones"
  type        = list(string)
}

variable "endpoint_private_access" {
  description = "Enable private VPC access to the Kubernetes API server"
  type        = bool
  default     = true
}

variable "endpoint_public_access" {
  description = "Enable public internet access to the Kubernetes API server"
  type        = bool
  default     = true
}

variable "public_access_cidrs" {
  description = "List of trusted CIDR blocks permitted to reach the public EKS API endpoint"
  type        = list(string)
}

variable "service_ipv4_cidr" {
  description = "CIDR block for Kubernetes ClusterIP Services (must not overlap with VPC CIDR)"
  type        = string
  default     = "172.20.0.0/16"
}

variable "enabled_cluster_log_types" {
  description = "List of EKS control plane log streams to send to CloudWatch Logs"
  type        = list(string)
  default = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]
}

variable "log_retention_in_days" {
  description = "Retention period in days for EKS control-plane CloudWatch logs"
  type        = number
  default     = 30
}

variable "kms_key_arn" {
  description = "Customer-managed KMS Key ARN for envelope encryption of Kubernetes Secrets"
  type        = string
}

variable "node_groups" {
  description = "Map of Managed Node Group definitions (system, application, monitoring)"
  type = map(object({
    instance_types = list(string)
    capacity_type  = string
    disk_size      = number
    min_size       = number
    desired_size   = number
    max_size       = number
    labels         = map(string)
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
  }))
}

variable "access_entries" {
  description = "Map of EKS Access Entries mapping IAM Role ARNs to Kubernetes access policies and scopes"
  type = map(object({
    principal_arn     = string
    policy_arn        = string
    access_scope_type = string
    namespaces        = optional(list(string), [])
  }))
  default = {}
}

variable "tags" {
  description = "Additional tags applied to all EKS module resources"
  type        = map(string)
  default     = {}
}
