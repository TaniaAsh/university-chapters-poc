variable "project_id" {
  description = "GCP project ID for the POC"
  type        = string
  default     = "university-chapters-poc"
}

variable "region" {
  description = "GCP region for all resources"
  type        = string
  default     = "europe-west2"
}
variable "ingestion_image" {
  description = "Container image for the ingestion Cloud Run Job. Placeholder until you build and push the real one."
  type        = string
  default     = "us-docker.pkg.dev/cloudrun/container/hello"
}

variable "dbt_image" {
  description = "Container image for the dbt transformation Cloud Run Job. Placeholder until you build and push the real one."
  type        = string
  default     = "us-docker.pkg.dev/cloudrun/container/hello"
}
variable "billing_account_id" {
  description = "Billing account ID to attach the budget alert to. Find it with: gcloud billing accounts list"
  type        = string
  # No default on purpose -- this is account-specific, supply it via terraform.tfvars (gitignored).
}

variable "budget_amount_gbp" {
  description = "Monthly budget threshold in GBP for the cost-guardrail alert"
  type        = number
  default     = 5
}
