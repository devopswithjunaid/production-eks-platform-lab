variable "environment" {
  description = "Environment name"
  type        = string
}

variable "project" {
  description = "Project name"
  type        = string
}

variable "repositories" {
  description = "List of ECR repository names"
  type        = list(string)
}

variable "kms_key_arn" {
  description = "KMS key ARN for ECR encryption"
  type        = string
}
