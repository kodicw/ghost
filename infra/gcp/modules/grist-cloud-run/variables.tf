# Cloud Run service for Grist

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "prefix" {
  description = "Resource name prefix"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
}

variable "grist_image" {
  description = "Grist container image"
  type        = string
}

variable "cpu" {
  description = "CPU limit"
  type        = string
}

variable "memory" {
  description = "Memory limit"
  type        = string
}

variable "min_instances" {
  description = "Minimum instances"
  type        = number
}

variable "max_instances" {
  description = "Maximum instances"
  type        = number
}

variable "concurrency" {
  description = "Max concurrent requests per instance"
  type        = number
}

variable "domain" {
  description = "Grist APP_HOME_URL"
  type        = string
}

variable "grist_session_secret" {
  description = "Grist session secret"
  type        = string
  sensitive   = true
}

variable "grist_boot_key" {
  description = "Grist boot key"
  type        = string
  default     = null
  sensitive   = true
}

variable "grist_api_key" {
  description = "Grist API key"
  type        = string
  default     = null
  sensitive   = true
}

variable "grist_single_org" {
  description = "Grist single org"
  type        = string
}

variable "db_connection_name" {
  description = "Cloud SQL connection name"
  type        = string
}

variable "db_name" {
  description = "Database name"
  type        = string
}

variable "db_user" {
  description = "Database user"
  type        = string
}

variable "db_password" {
  description = "Database password"
  type        = string
  sensitive   = true
}

variable "storage_bucket" {
  description = "GCS bucket name for document storage"
  type        = string
}

variable "connector_id" {
  description = "Serverless VPC Access connector ID"
  type        = string
}

variable "service_account_email" {
  description = "Service account email for Cloud SQL IAM"
  type        = string
  default     = null
}

variable "labels" {
  description = "Common resource labels"
  type        = map(string)
}
