# Cost guardrail matching the HLD's Scalability & Cost Control section:
# alert at 50/90/100% of a small monthly threshold. This does not stop
# spend -- it notifies the billing account admins by email -- but for a
# POC at this scale it's the right level of protection.

data "google_project" "current" {
  project_id = var.project_id
}

resource "google_billing_budget" "poc_guardrail" {
  billing_account = var.billing_account_id
  display_name    = "university-chapters-poc guardrail"

  budget_filter {
    projects = ["projects/${data.google_project.current.number}"]
  }

  amount {
    specified_amount {
      currency_code = "GBP"
      units         = tostring(var.budget_amount_gbp)
    }
  }

  threshold_rules {
    threshold_percent = 0.5
  }
  threshold_rules {
    threshold_percent = 0.9
  }
  threshold_rules {
    threshold_percent = 1.0
  }

  depends_on = [google_project_service.apis]
}