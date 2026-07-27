# Daily trigger, calling the Cloud Run Admin API to start the ingestion job.
# 05:00 UTC leaves a buffer before the 08:00 UTC publish SLA in the HLD
# data product contract (section 5).

resource "google_cloud_scheduler_job" "daily_ingestion_trigger" {
  project   = var.project_id
  region    = var.region
  name      = "daily-ingestion-trigger"
  schedule  = "0 5 * * *"
  time_zone = "Etc/UTC"

  http_target {
    http_method = "POST"
    uri         = "https://run.googleapis.com/v2/projects/${var.project_id}/locations/${var.region}/jobs/${google_cloud_run_v2_job.ingestion.name}:run"
    body        = base64encode("{}")

    headers = {
      "Content-Type" = "application/json"
    }

    oidc_token {
      service_account_email = google_service_account.ingestion.email
    }
  }

  depends_on = [
    google_project_service.apis,
    google_cloud_run_v2_job_iam_member.scheduler_invokes_ingestion,
  ]
}