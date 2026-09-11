output "network_name" {
  description = "VPC network name"
  value       = google_compute_network.main.name
}

output "network_self_link" {
  description = "VPC network self link"
  value       = google_compute_network.main.self_link
}

output "vpc_self_link" {
  description = "Alias for vpc self link"
  value       = google_compute_network.main.self_link
}

output "subnet_name" {
  description = "Subnet name"
  value       = google_compute_subnetwork.main.name
}

output "connector_id" {
  description = "Serverless VPC Access connector ID"
  value       = google_vpc_access_connector.main.id
}
