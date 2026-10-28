# Named workspaces (sandbox/staging/production) store state under
# env:/<workspace>/<key>; without `workspace` this block would silently read
# the default workspace's state, which does not exist in this layout.
data "terraform_remote_state" "network" {
  backend   = "s3"
  workspace = terraform.workspace

  config = {
    bucket = var.remote_backend.bucket
    key    = "networking/networking.tfstate"
    region = var.remote_backend.region
  }
}

data "aws_caller_identity" "current" {}

locals {
  vpc_id             = data.terraform_remote_state.network.outputs.vpc.id
  public_subnet_ids  = data.terraform_remote_state.network.outputs.public_subnets_ids
  private_subnet_ids = data.terraform_remote_state.network.outputs.private_subnets_ids
  admin_principal    = coalesce(var.eks.admin_principal_arn, data.aws_caller_identity.current.arn)
}

# Trust policies for the two IAM roles in eks-iam-role.tf.
data "aws_iam_policy_document" "cluster_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "node_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}
