output "grist_cloud_run_url" {
  description = "URL of the Grist Cloud Run service"
  value       = module.grist_cloud_run.service_url
}

output "grist_cloud_run_name" {
  description = "Name of the Grist Cloud Run service"
  value       = module.grist_cloud_run.service_name
}

output "grist_database_connection_name" {
  description = "Cloud SQL connection name for Grist"
  value       = module.grist_database.connection_name
}

output "grist_database_public_ip" {
  description = "Public IP of the Grist database (if enabled)"
  value       = module.grist_database.public_ip
}

output "grist_storage_bucket" {
  description = "GCS bucket for Grist document storage"
  value       = module.grist_storage.bucket_name
}

output "grist_image_repository" {
  description = "Artifact Registry repository for Grist images"
  value       = module.artifact_registry.repository_name
}

output "grist_image_repository_url" {
  description = "Full Artifact Registry repository URL"
  value       = module.artifact_registry.repository_url
}

output "vpc_network_name" {
  description = "VPC network name"
  value       = module.vpc.network_name
}

output "vpc_connector_id" {
  description = "Serverless VPC Access connector ID"
  value       = module.vpc.connector_id
}
