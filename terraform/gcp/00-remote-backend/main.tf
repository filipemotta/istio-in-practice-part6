# Stack 00-remote-backend: the GCS bucket that holds the state of 01 and 02,
# and the project APIs the downstream stacks call.

terraform {
  required_version = ">= 1.10.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.9"
    }
  }

  # No backend block: this stack creates the state bucket, so its own state
  # stays local (out/terraform/). The lab destroys it last, after every
  # stack that lives in the bucket.
}

# Lab identity: the operator's credentials (GOOGLE_OAUTH_ACCESS_TOKEN or ADC).
# A production repo selects a service account per workspace and keeps the
# plan-only account as the fallback; here impersonation is used only when
# var.impersonation.service_account is set.
provider "google" {
  project        = var.impersonation.project_id
  region         = var.impersonation.region
  default_labels = var.labels

  impersonate_service_account = var.impersonation.service_account
}
