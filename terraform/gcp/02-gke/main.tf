# Stack 02-gke: zonal GKE Standard cluster with private nodes and a public
# endpoint restricted to the operator and to the EKS side (NAT gateway
# address), Workload Identity, one node pool on a dedicated service account
# and the firewall rule the Istio webhook needs. Network comes from 01.

terraform {
  required_version = ">= 1.10.0"

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
    prefix = "gke"
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
