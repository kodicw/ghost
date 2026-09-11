variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "client_name" {
  description = "Client name for resource naming and isolation"
  type        = string
  default     = "ghost"
}

# ── Grist ──────────────────────────────────────────────────────────

variable "grist_image" {
  description = "Grist container image (Artifact Registry path)"
  type        = string
  default     = "gristlabs/grist:latest"
}

variable "grist_cpu" {
  description = "Cloud Run CPU limit for Grist"
  type        = string
  default     = "2"
}

variable "grist_memory" {
  description = "Cloud Run memory limit for Grist"
  type        = string
  default     = "1Gi"
}

variable "grist_min_instances" {
  description = "Minimum number of Cloud Run instances for Grist"
  type        = number
  default     = 0
}

variable "grist_max_instances" {
  description = "Maximum number of Cloud Run instances for Grist"
  type        = number
  default     = 3
}

variable "grist_concurrency" {
  description = "Max concurrent requests per Cloud Run instance"
  type        = number
  default     = 80
}

variable "grist_session_secret" {
  description = "Session secret for Grist (provide via tfvars or Secret Manager)"
  type        = string
  sensitive   = true
}

variable "grist_boot_key" {
  description = "Boot key for Grist first-run setup"
  type        = string
  sensitive   = true
  default     = null
}

variable "grist_api_key" {
  description = "API key for Grist management API"
  type        = string
  sensitive   = true
  default     = null
}

variable "grist_single_org" {
  description = "Single org mode for Grist"
  type        = string
  default     = "docs"
}

variable "grist_app_home_url" {
  description = "Public URL for Grist"
  type        = string
}

# ── Database ───────────────────────────────────────────────────────

variable "db_tier" {
  description = "Cloud SQL tier (e.g. db-f1-micro, db-g1-small, db-n1-standard-1)"
  type        = string
  default     = "db-f1-micro"
}

variable "db_disk_size" {
  description = "Cloud SQL disk size in GB"
  type        = number
  default     = 10
}

variable "db_disk_auto_resize" {
  description = "Automatically grow Cloud SQL disk"
  type        = bool
  default     = true
}

variable "db_disk_auto_resize_limit" {
  description = "Maximum disk size in GB for auto-resize"
  type        = number
  default     = 100
}

variable "db_name" {
  description = "Database name for Grist"
  type        = string
  default     = "grist"
}

variable "db_password" {
  description = "Database password (provide via tfvars or generated)"
  type        = string
  sensitive   = true
  default     = null
}

# ── Storage ────────────────────────────────────────────────────────

variable "storage_bucket_location" {
  description = "GCS bucket location"
  type        = string
  default     = "US"
}

variable "storage_retention_days" {
  description = "Object retention days for document backups"
  type        = number
  default     = 30
}

# ── Networking ─────────────────────────────────────────────────────

variable "vpc_name" {
  description = "VPC network name"
  type        = string
  default     = "ghost-vpc"
}

variable "vpc_subnet_cidr" {
  description = "CIDR block for the VPC subnet"
  type        = string
  default     = "10.0.0.0/24"
}
