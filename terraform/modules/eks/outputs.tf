output "cluster_name" {
  description = "EKS cluster name"
  value       = var.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = ""
}

output "cluster_ca_certificate" {
  description = "EKS cluster CA certificate"
  value       = ""
}
