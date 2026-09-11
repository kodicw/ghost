resource "google_compute_network" "main" {
  name                    = "${var.prefix}-${var.vpc_name}"
  project                 = var.project_id
  auto_create_subnetworks = false
  description             = "VPC for ${var.prefix} Ghost deployment"

  labels = var.labels
}

resource "google_compute_subnetwork" "main" {
  name          = "${var.prefix}-subnet"
  project       = var.project_id
  network       = google_compute_network.main.id
  region        = var.region
  ip_cidr_range = var.subnet_cidr
  description   = "Subnet for ${var.prefix} Ghost deployment"

  private_ip_google_access = true

  labels = var.labels
}

# Serverless VPC Access connector for Cloud Run to reach Cloud SQL privately
resource "google_vpc_access_connector" "main" {
  name          = "${var.prefix}-vpc-connector"
  project       = var.project_id
  region        = var.region
  network       = google_compute_network.main.name
  ip_cidr_range = cidrsubnet(var.subnet_cidr, 8, 0)

  # Machine type: e2-micro is the smallest
  machine_type  = "e2-micro"
  min_instances = 2
  max_instances = 3
}
