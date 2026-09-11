# Random password if none provided
resource "random_password" "db" {
  count  = var.db_password == null ? 1 : 0
  length = 32
  special = false
}

locals {
  db_password = var.db_password != null ? var.db_password : random_password.db[0].result
}

# Private services access connection
resource "google_compute_global_address" "private_ip" {
  name          = "${var.prefix}-private-ip-range"
  project       = var.project_id
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = var.vpc_self_link
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = var.vpc_self_link
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip.name]
}

# Cloud SQL Postgres instance
resource "google_sql_database_instance" "main" {
  name             = "${var.prefix}-grist-db"
  project          = var.project_id
  region           = var.region
  database_version = "POSTGRES_16"

  settings {
    tier              = var.db_tier
    disk_size         = var.db_disk_size
    disk_autoresize   = var.db_disk_auto_resize
    disk_autoresize_limit = var.db_disk_auto_resize_limit

    # Private IP only (no public IP)
    ip_configuration {
      ipv4_enabled    = false
      private_network = var.vpc_self_link

      # Allow Cloud Run via Serverless VPC Access
      require_ssl = true
    }

    # Automated backups with 7-day retention
    backup_configuration {
      enabled                        = true
      start_time                     = "03:00"
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = 7
      backup_retention_settings {
        retained_backups = 7
        retention_unit   = "COUNT"
      }
    }

    # Maintenance window (Sunday 4-5 AM)
    maintenance_window {
      day          = 7
      hour         = 4
      update_track = "stable"
    }

    # Connection pooling for Cloud Run
    database_flags {
      name  = "max_connections"
      value = "100"
    }

    # SSL enforcement
    database_flags {
      name  = "ssl_min_protocol_version"
      value = "TLSv1.2"
    }

    user_labels = var.labels
  }

  # Wait for private services connection
  depends_on = [google_service_networking_connection.private_vpc_connection]
}

# Database
resource "google_sql_database" "main" {
  name     = var.db_name
  project  = var.project_id
  instance = google_sql_database_instance.main.name
}

# User
resource "google_sql_user" "main" {
  name     = "grist"
  project  = var.project_id
  instance = google_sql_database_instance.main.name
  password = local.db_password
}
