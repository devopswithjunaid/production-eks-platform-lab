output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "The CIDR block of the VPC"
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "List of IDs of public subnets"
  value       = aws_subnet.public[*].id
}

output "private_eks_subnet_ids" {
  description = "List of IDs of private EKS subnets"
  value       = aws_subnet.private_eks[*].id
}

output "private_data_subnet_ids" {
  description = "List of IDs of private data subnets"
  value       = aws_subnet.private_data[*].id
}

output "nat_gateway_ids" {
  description = "List of NAT Gateway IDs"
  value       = aws_nat_gateway.this[*].id
}

output "availability_zones" {
  description = "List of Availability Zones configured in the VPC"
  value       = var.availability_zones
}
