# Cloud SQL Postgres instance for Grist

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

variable "vpc_self_link" {
  description = "VPC network self link for private services access"
  type        = string
}

variable "db_tier" {
  description = "Cloud SQL tier"
  type        = string
}

variable "db_disk_size" {
  description = "Disk size in GB"
  type        = number
}

variable "db_disk_auto_resize" {
  description = "Enable auto disk resize"
  type        = bool
}

variable "db_disk_auto_resize_limit" {
  description = "Max disk size in GB"
  type        = number
}

variable "db_name" {
  description = "Database name"
  type        = string
}

variable "db_password" {
  description = "Database password (auto-generated if null)"
  type        = string
  default     = null
  sensitive   = true
}

variable "labels" {
  description = "Common resource labels"
  type        = map(string)
}
