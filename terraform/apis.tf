# Every resource in this POC depends on its API being enabled first.
# Terraform will enable these before touching anything else, since every
# other resource file implicitly depends on them.

locals {
  required_apis = [
    "run.googleapis.com",                 # Cloud Run Jobs
    "cloudscheduler.googleapis.com",       # Cloud Scheduler
    "artifactregistry.googleapis.com",     # Artifact Registry
    "bigquery.googleapis.com",             # BigQuery
    "storage.googleapis.com",              # Cloud Storage
    "secretmanager.googleapis.com",        # Secret Manager
    "iam.googleapis.com",                  # Service accounts, Workload Identity
    "iamcredentials.googleapis.com",       # Workload Identity Federation token exchange
    "billingbudgets.googleapis.com",       # Budget alerts
    "cloudresourcemanager.googleapis.com", # Project-level IAM bindings
  ]
}

resource "google_project_service" "apis" {
  for_each = toset(local.required_apis)

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}