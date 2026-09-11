output "repository_name" {
  description = "Artifact Registry repository name"
  value       = google_artifact_registry_repository.main.name
}

output "repository_id" {
  description = "Artifact Registry repository ID"
  value       = google_artifact_registry_repository.main.repository_id
}

output "repository_url" {
  description = "Full repository URL for docker push/pull"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.main.repository_id}"
}
