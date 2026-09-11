output "connection_name" {
  description = "Cloud SQL instance connection name"
  value       = google_sql_database_instance.main.connection_name
}

output "instance_name" {
  description = "Cloud SQL instance name"
  value       = google_sql_database_instance.main.name
}

output "public_ip" {
  description = "Public IP address (empty if private IP only)"
  value       = google_sql_database_instance.main.public_ip_address
}

output "private_ip" {
  description = "Private IP address"
  value       = google_sql_database_instance.main.private_ip_address
}

output "db_name" {
  description = "Database name"
  value       = google_sql_database.main.name
}

output "db_user" {
  description = "Database user"
  value       = google_sql_user.main.name
}

output "db_password" {
  description = "Database password"
  value       = local.db_password
  sensitive   = true
}

output "service_account_email" {
  description = "Cloud SQL service account email for IAM"
  value       = google_sql_database_instance.main.service_account_email_address
}
