variable "tags" {
  description = "Global tags injected by the provider default_tags block. Resources only add Name (plus the discovery tags listed in the stack README)."
  type        = map(string)

  default = {
    "Project"   = "istio-p6"
    "Env"       = "lab"
    "region"    = "us-east-1"
    "ManagedBy" = "terraform"
  }
}

variable "assume_role" {
  description = "Region and optional role for the provider. The lab runs on the operator's credentials (AWS_PROFILE) with role_arn = null; set a role ARN to run through a delegated role."
  type = object({
    role_arn = string
    region   = string
  })

  default = {
    role_arn = null
    region   = "us-east-1"
  }
}

variable "remote_backend" {
  description = "State bucket. The name is <name_prefix>-<account ID>-<condensed region>-tfstate, unique per account."
  type = object({
    name_prefix   = string
    sse_algorithm = string
    force_destroy = bool
  })

  default = {
    name_prefix   = "istio-p6"
    sse_algorithm = "AES256"
    # Lab value: the teardown destroys the bucket with its versions inside.
    force_destroy = true
  }
}
