output "service_name" {
  description = "Cloud Run service name"
  value       = google_cloud_run_v2_service.main.name
}

output "service_url" {
  description = "Cloud Run service URL"
  value       = google_cloud_run_v2_service.main.uri
}

output "service_location" {
  description = "Cloud Run service location"
  value       = google_cloud_run_v2_service.main.location
}

output "latest_revision" {
  description = "Latest ready revision name"
  value       = google_cloud_run_v2_service.main.latest_ready_revision
}
