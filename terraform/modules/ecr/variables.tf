variable "environment" {
  description = "Deployment environment (dev / staging / production)"
  type        = string
}

variable "project" {
  description = "Project name used for resource naming and tagging"
  type        = string
}

variable "repositories" {
  description = "List of ECR repository names to create (will be prefixed with project name)"
  type        = list(string)
}

variable "kms_key_arn" {
  description = "Customer-managed KMS key ARN for ECR image encryption at rest"
  type        = string
}

variable "lifecycle_keep_count" {
  description = "Maximum number of tagged images to retain per repository before expiring older ones"
  type        = number
  default     = 30
}
