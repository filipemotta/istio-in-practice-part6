variable "labels" {
  description = "Global labels injected by the provider default_labels argument. Resources add nothing else; their identity is the name argument."
  type        = map(string)

  default = {
    "project"    = "istio-p6"
    "env"        = "lab"
    "region"     = "us-east4"
    "managed_by" = "terraform"
  }
}

variable "impersonation" {
  description = "Project, region and optional service account for the provider. The lab runs on the operator's credentials with service_account = null; scripts/lib.sh sets project_id through TF_VAR_impersonation."
  type = object({
    project_id      = string
    region          = string
    service_account = string
  })

  default = {
    project_id      = ""
    region          = "us-east4"
    service_account = null
  }

  validation {
    condition     = var.impersonation.project_id != ""
    error_message = "Set impersonation.project_id (scripts/lib.sh exports TF_VAR_impersonation)."
  }
}

variable "vpc" {
  description = "Network layout. One regional subnet replaces the AWS public/private pairs; secondary ranges feed GKE (VPC-native). Cloud NAT gives private nodes egress."
  type = object({
    name         = string
    routing_mode = string
    subnetwork = object({
      name                     = string
      ip_cidr_range            = string
      private_ip_google_access = bool
      secondary_ip_ranges = list(object({
        range_name    = string
        ip_cidr_range = string
      }))
    })
    router_name    = string
    nat_name       = string
    nat_address    = string
    nat_log_filter = string
  })

  default = {
    name         = "vpc-istio-p6-useast4"
    routing_mode = "REGIONAL"
    subnetwork = {
      name                     = "subnet-istio-p6-useast4"
      ip_cidr_range            = "10.20.0.0/20"
      private_ip_google_access = true
      secondary_ip_ranges = [
        {
          range_name    = "pods"
          ip_cidr_range = "10.21.0.0/16"
        },
        {
          range_name    = "services"
          ip_cidr_range = "10.22.0.0/20"
        },
      ]
    }
    router_name    = "router-istio-p6-useast4"
    nat_name       = "nat-istio-p6-useast4"
    nat_address    = "address-nat-istio-p6-useast4"
    nat_log_filter = "ERRORS_ONLY"
  }
}
