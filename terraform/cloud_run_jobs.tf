# Two separate jobs (ADR-002 in the HLD: keep ingestion and transformation
# separate so dbt can be rerun without re-calling the external API).
#
# IMPORTANT ORDERING NOTE: both jobs default to a public placeholder image
# (see variables.tf) so `terraform apply` succeeds even before you've built
# and pushed the real ingestion/dbt images. Once you've built and pushed
# them to the Artifact Registry repo above, override ingestion_image and
# dbt_image in terraform.tfvars and re-apply.

resource "google_cloud_run_v2_job" "dbt" {
  name     = "dbt-transform-job"
  project  = var.project_id
  location = var.region

  template {
    template {
      service_account = google_service_account.dbt_transform.email
      max_retries      = 1
      timeout          = "600s"

      containers {
        image = var.dbt_image

        resources {
          limits = {
            cpu    = "1"
            memory = "512Mi"
          }
        }

        env {
          name  = "BQ_PROJECT"
          value = var.project_id
        }
        env {
          name  = "BQ_DATASET_RAW"
          value = google_bigquery_dataset.raw.dataset_id
        }
        env {
          name  = "BQ_DATASET_CURATED"
          value = google_bigquery_dataset.curated.dataset_id
        }
        env {
          name  = "BQ_DATASET_PUBLISHED"
          value = google_bigquery_dataset.published.dataset_id
        }
        env {
          name  = "REGION"
          value = var.region
        }
      }
    }
  }

  depends_on = [google_project_service.apis]
}

resource "google_cloud_run_v2_job" "ingestion" {
  name     = "ingestion-job"
  project  = var.project_id
  location = var.region

  template {
    template {
      service_account = google_service_account.ingestion.email
      max_retries      = 1
      timeout          = "300s"

      containers {
        image = var.ingestion_image

        resources {
          limits = {
            cpu    = "1"
            memory = "512Mi"
          }
        }

        env {
          name  = "BUCKET_NAME"
          value = google_storage_bucket.landing.name
        }
        env {
          name  = "BQ_PROJECT"
          value = var.project_id
        }
        env {
          name  = "BQ_DATASET_RAW"
          value = google_bigquery_dataset.raw.dataset_id
        }
        env {
          name  = "DBT_JOB_NAME"
          value = google_cloud_run_v2_job.dbt.name
        }
        env {
          name  = "REGION"
          value = var.region
        }
      }
    }
  }

  depends_on = [google_project_service.apis]
}

# Cloud Scheduler's OIDC token (identity = ingestion SA) needs invoker
# rights to start the ingestion job.
resource "google_cloud_run_v2_job_iam_member" "scheduler_invokes_ingestion" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_job.ingestion.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.ingestion.email}"
}

# The ingestion job's own code calls the Cloud Run Admin API to start the
# dbt job -- so the ingestion SA also needs invoker rights on the dbt job.
resource "google_cloud_run_v2_job_iam_member" "ingestion_invokes_dbt" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_job.dbt.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.ingestion.email}"
}