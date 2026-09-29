variable "aws_region" {
  description = "AWS region where the Terraform state S3 bucket will be created"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name used for bucket naming"
  type        = string
  default     = "production-eks-platform-lab"
}
