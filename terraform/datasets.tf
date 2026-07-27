# Mirrors the three-layer physical model from the HLD (section 4.2):
# raw -> curated -> published, each as its own dataset so access controls
# and lifecycle can differ per layer even though this POC keeps them simple.

resource "google_bigquery_dataset" "raw" {
  dataset_id  = "university_ch_raw"
  project     = var.project_id
  location    = var.region
  description = "Source-aligned, append-only landing zone for chapter data."

  depends_on = [google_project_service.apis]
}

resource "google_bigquery_dataset" "curated" {
  dataset_id  = "university_ch_curated"
  project     = var.project_id
  location    = var.region
  description = "Cleaned, validated canonical chapter_snapshot table, built by dbt."

  depends_on = [google_project_service.apis]
}

resource "google_bigquery_dataset" "published" {
  dataset_id  = "university_ch_published"
  project     = var.project_id
  location    = var.region
  description = "Stable, versioned consumer interface (university_chapters_v1)."

  depends_on = [google_project_service.apis]
}