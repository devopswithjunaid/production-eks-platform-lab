output "vpc_id" {
  description = "VPC ID"
  value       = ""
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = []
}

output "private_eks_subnet_ids" {
  description = "List of private EKS subnet IDs"
  value       = []
}

output "private_data_subnet_ids" {
  description = "List of private data subnet IDs"
  value       = []
}
