variable "name" {
  description = "Base name for VPC resources (e.g., project name)"
  type        = string
}

variable "environment" {
  description = "Deployment environment (e.g., dev, staging, production)"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name used for Kubernetes subnet discovery tags"
  type        = string
}

variable "vpc_cidr" {
  description = "Primary IPv4 CIDR block for the VPC"
  type        = string
}

variable "availability_zones" {
  description = "List of Availability Zones in which to create subnets"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "List of CIDR blocks for public subnets (one per AZ)"
  type        = list(string)
}

variable "private_eks_subnet_cidrs" {
  description = "List of CIDR blocks for private EKS compute subnets (one per AZ)"
  type        = list(string)
}

variable "private_data_subnet_cidrs" {
  description = "List of CIDR blocks for isolated private data subnets (one per AZ)"
  type        = list(string)
}

variable "single_nat_gateway" {
  description = "If true, provision a single shared NAT Gateway in AZ-A (cost-optimized for dev). If false, provision one NAT Gateway per AZ (HA for prod)."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags to apply to all VPC resources"
  type        = map(string)
  default     = {}
}
