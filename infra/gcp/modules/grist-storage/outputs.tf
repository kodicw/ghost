output "bucket_name" {
  description = "GCS bucket name"
  value       = google_storage_bucket.main.name
}

output "bucket_url" {
  description = "GCS bucket gs:// URL"
  value       = "gs://${google_storage_bucket.main.name}"
}

output "bucket_self_link" {
  description = "GCS bucket self link"
  value       = google_storage_bucket.main.self_link
}
