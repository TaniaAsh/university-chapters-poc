# Two identities, matching the HLD's least-privilege design (section 8):
# ingestion and transformation each get their own service account rather
# than sharing one broad identity.

resource "google_service_account" "ingestion" {
  project      = var.project_id
  account_id   = "ingestion-sa"
  display_name = "University Chapters - ingestion job"
}

resource "google_service_account" "dbt_transform" {
  project      = var.project_id
  account_id   = "dbt-transform-sa"
  display_name = "University Chapters - dbt transformation job"
}

# --- Ingestion SA: write to the landing bucket, write to raw, run jobs ---

resource "google_storage_bucket_iam_member" "ingestion_writes_landing" {
  bucket = google_storage_bucket.landing.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.ingestion.email}"
}

resource "google_bigquery_dataset_iam_member" "ingestion_writes_raw" {
  dataset_id = google_bigquery_dataset.raw.dataset_id
  project    = var.project_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.ingestion.email}"
}

resource "google_project_iam_member" "ingestion_runs_jobs" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.ingestion.email}"
}

# --- dbt SA: read raw, write curated + published, run jobs ---

resource "google_bigquery_dataset_iam_member" "dbt_writes_raw" {
  dataset_id = google_bigquery_dataset.raw.dataset_id
  project    = var.project_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.dbt_transform.email}"
}

resource "google_bigquery_dataset_iam_member" "dbt_writes_curated" {
  dataset_id = google_bigquery_dataset.curated.dataset_id
  project    = var.project_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.dbt_transform.email}"
}

resource "google_bigquery_dataset_iam_member" "dbt_writes_published" {
  dataset_id = google_bigquery_dataset.published.dataset_id
  project    = var.project_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.dbt_transform.email}"
}

resource "google_project_iam_member" "dbt_runs_jobs" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.dbt_transform.email}"
}