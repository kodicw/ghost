# ── Ghost GCP Infrastructure ──────────────────────────────────────

This directory contains [OpenTofu](https://opentofu.org) (OSS Terraform fork) configurations
for deploying Grist to Google Cloud Run.

## Architecture

```
User ──► Cloud Run (Grist)
              │
              ├──► Cloud SQL (Postgres 16) ── private IP ──┐
              │                                             │
              ├──► GCS Bucket (documents & backups)        │
              │                                             │
              └──► Serverless VPC Access Connector ────────┘
```

## What gets created

| Resource | Purpose |
|---|---|
| **Cloud Run** | Grist container (stateless, auto-scaling) |
| **Cloud SQL** | Postgres 16 database (private IP, SSL enforced) |
| **GCS Bucket** | Document storage with versioning & retention |
| **Artifact Registry** | Docker repo for pinned Grist images |
| **VPC** | Private network with Serverless VPC Access connector |
| **IAM** | Service accounts with least-privilege roles |

## Prerequisites

- [OpenTofu](https://opentofu.org/docs/intro/install/) >= 1.6
- GCP project with billing enabled
- APIs enabled:
  - `run.googleapis.com`
  - `sqladmin.googleapis.com`
  - `storage.googleapis.com`
  - `artifactregistry.googleapis.com`
  - `vpcaccess.googleapis.com`
  - `servicenetworking.googleapis.com`
- GCS bucket for remote state (see below)

## Setup

```bash
# 1. Set up remote state bucket
gsutil mb gs://ghost-tofu-state
gsutil versioning set on gs://ghost-tofu-state

# 2. Configure variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your project ID and secrets

# 3. Initialize
tofu init -backend-config="bucket=ghost-tofu-state" -backend-config="prefix=gcp"

# 4. Plan
tofu plan -out=tfplan

# 5. Apply
tofu apply tfplan
```

## Workflow

```bash
tofu fmt        # Format all files
tofu validate   # Check syntax
tofu plan       # Preview changes
tofu apply      # Apply changes
tofu destroy    # Tear down (careful!)
```

## Pinning a specific Grist version

```bash
# Pull the upstream image
docker pull gristlabs/grist:1.2.3

# Tag for Artifact Registry
docker tag gristlabs/grist:1.2.3 \
  us-central1-docker.pkg.dev/<project>/ghost-prod-grist/grist:1.2.3

# Push
docker push us-central1-docker.pkg.dev/<project>/ghost-prod-grist/grist:1.2.3

# Update terraform.tfvars
grist_image = "us-central1-docker.pkg.dev/<project>/ghost-prod-grist/grist:1.2.3"
```

## Dockhand

Dockhand is **not** deployed to Cloud Run — it requires `docker.sock` access which
Cloud Run doesn't support. It remains on the ghost NixOS host behind Tailscale,
managed via Ansible (`ansible/playbooks/dockhand.yml`).

## Next steps

1. Create a GCP project and enable APIs
2. Set up remote state bucket
3. Fill in `terraform.tfvars` with real values
4. Run `tofu init && tofu plan`
