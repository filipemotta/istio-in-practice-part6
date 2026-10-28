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
  description = "State bucket. The name is <project_id>-tfstate: project IDs are globally unique, so the bucket name is too."
  type = object({
    location      = string
    storage_class = string
    force_destroy = bool
  })

  default = {
    location      = "us-east4"
    storage_class = "STANDARD"
    # Lab value: the teardown destroys the bucket with its versions inside.
    force_destroy = true
  }
}

variable "project" {
  description = "Project-level bootstrap: the APIs the downstream stacks call."
  type = object({
    services = list(string)
  })

  default = {
    services = [
      "compute.googleapis.com",
      "container.googleapis.com",
      "iam.googleapis.com",
    ]
  }
}
