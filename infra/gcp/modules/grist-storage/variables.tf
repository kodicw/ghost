# GCS bucket for Grist document storage and backups

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "prefix" {
  description = "Resource name prefix"
  type        = string
}

variable "bucket_location" {
  description = "GCS bucket location"
  type        = string
}

variable "retention_days" {
  description = "Object retention period in days"
  type        = number
}

variable "labels" {
  description = "Common resource labels"
  type        = map(string)
}
