# Stores the ingestion and dbt container images -- matches Artifact Registry
# in the HLD architecture diagram.

resource "google_artifact_registry_repository" "images" {
  project       = var.project_id
  location      = var.region
  repository_id = "university-chapters"
  description   = "Docker images for the University Chapters ingestion and dbt jobs"
  format        = "DOCKER"

  depends_on = [google_project_service.apis]
}