variable "environment" {
  description = "Environment name"
  type        = string
}

variable "project" {
  description = "Project name"
  type        = string
}

variable "github_org" {
  description = "GitHub organization or user"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
}
