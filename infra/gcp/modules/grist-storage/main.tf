resource "google_storage_bucket" "main" {
  name          = "${var.prefix}-grist-documents"
  project       = var.project_id
  location      = var.bucket_location
  storage_class = "STANDARD"

  # Prevent accidental deletion
  force_destroy               = false
  uniform_bucket_level_access = true

  # Retention policy for document backups
  retention_policy {
    retention_period = var.retention_days * 86400 # seconds
  }

  # Versioning for document history
  versioning {
    enabled = true
  }

  # Object lifecycle: delete after retention + archive old versions
  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age = var.retention_days
    }
  }

  lifecycle_rule {
    action {
      type = "SetStorageClass"
      storage_class = "NEARLINE"
    }
    condition {
      age = 90
    }
  }

  labels = var.labels
}

# Bucket IAM: allow Cloud Run SA to read/write
resource "google_storage_bucket_iam_member" "cloud_run_access" {
  bucket = google_storage_bucket.main.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${var.project_id}@cloudservices.gserviceaccount.com"
}

# Public access prevention
resource "google_storage_bucket_iam_binding" "public_block" {
  bucket = google_storage_bucket.main.name
  role   = "roles/storage.objectViewer"
  members = []
}
