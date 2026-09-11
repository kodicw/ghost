# Cloud Run service for Grist

locals {
  # Build the DATABASE_URL from the Cloud SQL connection name
  database_url = "postgresql://${var.db_user}:${var.db_password}@/${var.db_name}?host=/cloudsql/${var.db_connection_name}"
}

resource "google_cloud_run_v2_service" "main" {
  name     = "${var.prefix}-grist"
  project  = var.project_id
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    scaling {
      min_instance_count = var.min_instances
      max_instance_count = var.max_instances
    }

    # Connect to Cloud SQL via the Cloud SQL proxy sidecar
    volumes {
      name = "cloudsql"
      cloud_sql_instance {
        instances = [var.db_connection_name]
      }
    }

    # VPC Access for private networking
    vpc_access {
      connector = var.connector_id
      egress    = "PRIVATE_RANGES_ONLY"
    }

    service_account = var.service_account_email

    containers {
      image = var.grist_image

      resources {
        limits = {
          cpu    = var.cpu
          memory = var.memory
        }
      }

      # Port Grist listens on
      ports {
        container_port = 8484
        name           = "http1"
      }

      # Mount Cloud SQL proxy socket
      volume_mounts {
        name       = "cloudsql"
        mount_path = "/cloudsql"
      }

      # ── Grist environment variables ────────────────────────────
      env {
        name  = "APP_HOME_URL"
        value = var.domain
      }

      env {
        name  = "GRIST_SINGLE_ORG"
        value = var.grist_single_org
      }

      env {
        name  = "GRIST_SESSION_SECRET"
        value = var.grist_session_secret
      }

      # Database: use Postgres via Unix socket
      env {
        name  = "GRIST_DATABASE_URL"
        value = local.database_url
      }

      # Disable SQLite (we use Cloud SQL)
      env {
        name  = "GRIST_SQLITE_DB"
        value = ""
      }

      # Document storage location (use GCS-backed mount in future)
      env {
        name  = "GRIST_DOCS_DIR"
        value = "/persist/docs"
      }

      # GCS integration for document storage
      env {
        name  = "GRIST_STORAGE_BUCKET"
        value = var.storage_bucket
      }

      env {
        name  = "GRIST_STORAGE_TYPE"
        value = "gcs"
      }

      # Boot key for first-run setup (optional after initial bootstrap)
      env {
        name  = "GRIST_BOOT_KEY"
        value = var.grist_boot_key != null ? var.grist_boot_key : ""
      }

      # API key for programmatic access
      env {
        name  = "GRIST_API_KEY"
        value = var.grist_api_key != null ? var.grist_api_key : ""
      }

      # Health check: Grist's built-in endpoint
      startup_probe {
        tcp_socket {
          port = 8484
        }
        initial_delay_seconds = 10
        timeout_seconds       = 5
        period_seconds        = 10
        failure_threshold     = 12
      }

      liveness_probe {
        http_get {
          path = "/status"
          port = 8484
        }
        initial_delay_seconds = 30
        timeout_seconds       = 5
        period_seconds        = 30
        failure_threshold     = 3
      }
    }

    # Timeouts
    timeout = "300s"

    # Use the default service account with minimal permissions
    # IAM roles are granted directly to this SA via separate bindings
  }

  # Traffic: 100% to latest revision
  traffic {
    type    = "TRAFFIC_RECENT_REVISIONS"
    percent = 100
  }

  labels = var.labels

  # Wait for the database to be ready
  depends_on = [
    # Implicit via var.db_connection_name
  ]
}

# Allow unauthenticated invocations (for public web app)
resource "google_cloud_run_v2_service_iam_member" "public_invoke" {
  project  = google_cloud_run_v2_service.main.project
  location = google_cloud_run_v2_service.main.location
  name     = google_cloud_run_v2_service.main.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# ── Cloud Run SA permissions ───────────────────────────────────────

# Cloud SQL Client for the proxy
resource "google_project_iam_member" "cloud_sql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${var.service_account_email}"
}
