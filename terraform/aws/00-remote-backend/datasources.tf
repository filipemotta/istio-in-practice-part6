data "aws_caller_identity" "current" {}

locals {
  state_bucket_name = "${var.remote_backend.name_prefix}-${data.aws_caller_identity.current.account_id}-useast1-tfstate"
}
