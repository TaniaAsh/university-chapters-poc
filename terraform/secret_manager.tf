# The Ducks Unlimited API is public and needs no key, so there is no real
# secret to store for this POC. This resource exists purely to demonstrate
# the Secret Manager pattern from the HLD (section 8) -- it holds a small
# piece of non-sensitive config, not an actual credential. If this product
# later needs a real secret (e.g. an API key for a different source), the
# same pattern applies: create the secret here, grant the relevant service
# account roles/secretmanager.secretAccessor, and read it at runtime rather
# than hardcoding it in the container image.

resource "google_secret_manager_secret" "poc_config" {
  project   = var.project_id
  secret_id = "poc-config-placeholder"

  replication {
    auto {}
  }

  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret_version" "poc_config" {
  secret      = google_secret_manager_secret.poc_config.id
  secret_data = jsonencode({
    note        = "Demonstrates the Secret Manager pattern; DU API requires no key."
    bucket_name = google_storage_bucket.landing.name
  })
}

resource "google_secret_manager_secret_iam_member" "ingestion_reads_config" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.poc_config.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.ingestion.email}"
}