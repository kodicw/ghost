locals {
  # Standardized resource name prefix
  prefix = "${var.client_name}-${var.environment}"

  # Common labels for all resources
  labels = {
    client      = var.client_name
    environment = var.environment
    managed_by  = "opentofu"
    project     = "ghost"
  }
}

# ── VPC + Serverless VPC Access ────────────────────────────────────

module "vpc" {
  source = "./modules/vpc"

  project_id       = var.project_id
  prefix           = local.prefix
  vpc_name         = var.vpc_name
  subnet_cidr      = var.vpc_subnet_cidr
  region           = var.region
  labels           = local.labels
}

# ── Artifact Registry (pinned Grist image) ─────────────────────────

module "artifact_registry" {
  source = "./modules/artifact-registry"

  project_id = var.project_id
  prefix     = local.prefix
  region     = var.region
  labels     = local.labels
}

# ── Cloud SQL (Postgres for Grist) ─────────────────────────────────

module "grist_database" {
  source = "./modules/grist-database"

  project_id              = var.project_id
  prefix                  = local.prefix
  region                  = var.region
  vpc_self_link           = module.vpc.vpc_self_link
  db_tier                 = var.db_tier
  db_disk_size            = var.db_disk_size
  db_disk_auto_resize     = var.db_disk_auto_resize
  db_disk_auto_resize_limit = var.db_disk_auto_resize_limit
  db_name                 = var.db_name
  db_password             = var.db_password
  labels                  = local.labels
}

# ── GCS Bucket (Grist document storage) ────────────────────────────

module "grist_storage" {
  source = "./modules/grist-storage"

  project_id             = var.project_id
  prefix                 = local.prefix
  bucket_location        = var.storage_bucket_location
  retention_days         = var.storage_retention_days
  labels                 = local.labels
}

# ── Cloud Run (Grist service) ──────────────────────────────────────

module "grist_cloud_run" {
  source = "./modules/grist-cloud-run"

  project_id    = var.project_id
  prefix        = local.prefix
  region        = var.region

  grist_image   = var.grist_image
  cpu           = var.grist_cpu
  memory        = var.grist_memory
  min_instances = var.grist_min_instances
  max_instances = var.grist_max_instances
  concurrency   = var.grist_concurrency

  domain               = var.grist_app_home_url
  grist_session_secret = var.grist_session_secret
  grist_boot_key       = var.grist_boot_key
  grist_api_key        = var.grist_api_key
  grist_single_org     = var.grist_single_org

  db_connection_name = module.grist_database.connection_name
  db_name            = module.grist_database.db_name
  db_user            = module.grist_database.db_user
  db_password        = module.grist_database.db_password

  storage_bucket        = module.grist_storage.bucket_name
  connector_id          = module.vpc.connector_id

  service_account_email = module.grist_database.service_account_email

  labels = local.labels
}
