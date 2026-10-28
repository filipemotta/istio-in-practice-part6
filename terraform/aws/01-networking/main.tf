# Stack 01-networking: VPC, two AZs, public + private subnets, IGW, one NAT
# gateway (single NAT on purpose: lab cost), route tables. The NAT EIP is the
# address GKE sees when EKS calls it, so the GKE side allow-lists it.

terraform {
  required_version = ">= 1.11.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.70"
    }
  }

  # Partial configuration: the bucket name carries the account ID, so
  # scripts/lib.sh passes it with -backend-config=bucket=... at init.
  backend "s3" {
    key          = "networking/networking.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
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
