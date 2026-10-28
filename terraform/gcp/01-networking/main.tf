# Stack 01-networking: custom VPC, one regional subnet with secondary ranges
# for GKE, Cloud Router and Cloud NAT on a reserved static address. That
# address is the source of every call GKE makes to EKS, so the EKS side
# allow-lists it.

terraform {
  required_version = ">= 1.11.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.9"
    }
  }

  # Partial configuration: the bucket is named after the project, so
  # scripts/lib.sh passes it with -backend-config=bucket=... at init. GCS
  # locks natively and encrypts at rest by default.
  backend "gcs" {
    prefix = "networking"
  }
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
