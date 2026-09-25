variable "environment" {
  description = "Environment name"
  type        = string
}

variable "project" {
  description = "Project name"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
}

variable "availability_zones" {
  description = "List of Availability Zones"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDR blocks"
  type        = list(string)
}

variable "private_eks_cidrs" {
  description = "Private EKS subnet CIDR blocks"
  type        = list(string)
}

variable "private_data_cidrs" {
  description = "Private Data subnet CIDR blocks"
  type        = list(string)
}

variable "single_nat_gateway" {
  description = "Use a single shared NAT Gateway"
  type        = bool
  default     = true
}
