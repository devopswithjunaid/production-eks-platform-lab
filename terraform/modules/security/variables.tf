variable "environment" {
  description = "Deployment environment (dev / staging / production)"
  type        = string
}

variable "project" {
  description = "Project name used for resource naming and tagging"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name used for VPC endpoint tagging and naming"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID in which to create security groups and VPC endpoints"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block used for security group ingress rules"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private EKS subnet IDs in which to place VPC interface endpoints"
  type        = list(string)
}

variable "kms_key_arn" {
  description = "KMS key ARN for CloudTrail log encryption"
  type        = string
}

variable "enable_guardduty" {
  description = "Enable GuardDuty detector for threat detection"
  type        = bool
  default     = true
}

variable "cloudtrail_retention_days" {
  description = "CloudWatch log retention in days for CloudTrail events"
  type        = number
  default     = 90
}

variable "tags" {
  description = "Additional tags to apply to all security resources"
  type        = map(string)
  default     = {}
}
