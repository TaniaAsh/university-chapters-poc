terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  # For a solo POC, local state is fine. The production HLD specifies
  # remote state per environment in GCS (see ADR-006) -- if you later
  # want to mirror that here, uncomment and fill in a bucket name:
  #
  # backend "gcs" {
  #   bucket = "university-chapters-poc-tfstate"
  #   prefix = "poc"
  # }
}

provider "google" {
  project = var.project_id
  region  = var.region
  user_project_override = true
  billing_project       = var.project_id
}