# Stack 00-remote-backend: the S3 bucket that holds the state of 01 and 02.

terraform {
  required_version = ">= 1.11.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.70"
    }
  }

  # No backend block: this stack creates the state bucket, so its own state
  # stays local (out/terraform/). The lab destroys it last, after every
  # stack that lives in the bucket.
}

# Lab identity: the operator's credentials (AWS_PROFILE). A production repo
# selects a role per workspace and keeps the plan-only role as the fallback;
# here assume_role is used only when var.assume_role.role_arn is set.
provider "aws" {
  region = var.assume_role.region

  default_tags {
    tags = var.tags
  }

  dynamic "assume_role" {
    for_each = var.assume_role.role_arn == null ? [] : [var.assume_role.role_arn]

    content {
      role_arn = assume_role.value
    }
  }
}
