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

variable "remote_backend" {
  description = "Where the upstream stacks keep their state. The bucket is <project_id>-tfstate, so scripts/lib.sh sets it through TF_VAR_remote_backend."
  type = object({
    bucket = string
  })

  default = {
    bucket = ""
  }

  validation {
    condition     = var.remote_backend.bucket != ""
    error_message = "Set remote_backend.bucket (scripts/lib.sh exports TF_VAR_remote_backend)."
  }
}

variable "api_access" {
  description = "CIDRs allowed to reach the public GKE endpoint: the operator running the lab and the AWS NAT gateway address (istiod in EKS reads this API). scripts/lib.sh sets it through TF_VAR_api_access."
  type = object({
    authorized_cidrs = list(object({
      display_name = string
      cidr_block   = string
    }))
  })

  default = {
    authorized_cidrs = []
  }

  validation {
    condition     = length(var.api_access.authorized_cidrs) > 0 && !contains([for c in var.api_access.authorized_cidrs : c.cidr_block], "0.0.0.0/0")
    error_message = "The GKE endpoint must be allow-listed: at least one CIDR, never 0.0.0.0/0."
  }
}

variable "gke" {
  description = "Cluster, node pool and node identity configuration. location is a zone: a zonal cluster keeps the lab to one zone of nodes."
  type = object({
    cluster_name                = string
    location                    = string
    release_channel             = string
    datapath_provider           = string
    enable_private_nodes        = bool
    enable_private_endpoint     = bool
    master_ipv4_cidr_block      = string
    deletion_protection         = bool
    istio_webhook_firewall_name = string
    node_service_account_id     = string
    node_service_account_roles  = list(string)
    node_pool = object({
      name         = string
      machine_type = string
      disk_size_gb = number
      disk_type    = string
      node_count   = number
      auto_repair  = bool
      auto_upgrade = bool
    })
  })

  default = {
    cluster_name            = "gke-cluster-istio-p6"
    location                = "us-east4-a"
    release_channel         = "REGULAR"
    datapath_provider       = "ADVANCED_DATAPATH"
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "10.23.0.0/28"
    # Lab value: a production stack sets deletion_protection = true.
    deletion_protection         = false
    istio_webhook_firewall_name = "firewall-istio-webhook-istio-p6-useast4"
    node_service_account_id     = "gke-node-istio-p6"
    node_service_account_roles = [
      "roles/logging.logWriter",
      "roles/monitoring.metricWriter",
      "roles/monitoring.viewer",
      "roles/artifactregistry.reader",
    ]
    node_pool = {
      name = "gke-node-pool-istio-p6"
      # Two vCPU and 8 GiB per node, the same budget as the EKS t3.large.
      machine_type = "e2-standard-2"
      disk_size_gb = 20
      disk_type    = "pd-balanced"
      node_count   = 2
      auto_repair  = true
      auto_upgrade = true
    }
  }
}
