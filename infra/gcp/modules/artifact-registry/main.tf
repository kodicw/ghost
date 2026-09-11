resource "google_artifact_registry_repository" "main" {
  project       = var.project_id
  location      = var.region
  repository_id = "${var.prefix}-grist"
  description   = "Container images for ${var.prefix} Grist deployment"
  format        = "DOCKER"

  # Cleanup policies: keep the 10 most recent images per tag
  cleanup_policies {
    id     = "keep-recent"
    action = "KEEP"
    most_recent_versions {
      keep_count = 10
    }
  }

  cleanup_policies {
    id      = "delete-untagged"
    action  = "DELETE"
    condition {
      tag_state    = "TAGGED"
      tag_prefixes = [""]
      older_than   = "2592000s" # 30 days
    }
  }

  labels = var.labels
}

# IAM: allow Cloud Run service account to pull images
resource "google_artifact_registry_repository_iam_member" "reader" {
  project    = google_artifact_registry_repository.main.project
  location   = google_artifact_registry_repository.main.location
  repository = google_artifact_registry_repository.main.name
  role       = "roles/artifactregistry.reader"
  member     = "allUsers" # Public pull — Cloud Run public services need this
}
