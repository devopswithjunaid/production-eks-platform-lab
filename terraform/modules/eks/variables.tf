variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "project" {
  description = "Project name"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private EKS subnet IDs"
  type        = list(string)
}

variable "node_security_group_id" {
  description = "EKS node security group ID"
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key ARN for EKS secret encryption"
  type        = string
}
