# Landing bucket for the raw API response, load-ready NDJSON, and ingestion
# metadata -- matches the Cloud Storage component in the HLD architecture.
# Lifecycle rule mirrors the HLD's cost-control decision: delete raw landing
# files after 90 days rather than keeping them forever.

resource "google_storage_bucket" "landing" {
  name     = "${var.project_id}-landing"
  project  = var.project_id
  location = var.region

  uniform_bucket_level_access = true
  force_destroy                = true # convenient for a POC; remove for anything longer-lived

  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type = "Delete"
    }
  }

  depends_on = [google_project_service.apis]
}