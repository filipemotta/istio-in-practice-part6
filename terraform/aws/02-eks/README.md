# aws/02-eks

## Purpose
EKS 1.36 on the private subnets of `01-networking`, with a public API endpoint allow-listed to two addresses: the operator and the GKE Cloud NAT address (istiod on GKE reads this API).

## Provisions
- `aws_iam_role.cluster` + `aws_iam_role_policy_attachment.cluster[*]`
- `aws_iam_role.node` + `aws_iam_role_policy_attachment.node[*]`
- `aws_eks_cluster.this` (authentication mode API, creator admin bootstrap off, `public_access_cidrs` from `var.api_access`)
- `aws_eks_node_group.this` (2 x t3.large, AL2023 x86_64, on-demand)
- `aws_eks_access_entry.admin` + `aws_eks_access_policy_association.admin` (cluster admin for the identity running apply, unless `admin_principal_arn` is set)

## Consumes
- `01-networking` via `data.terraform_remote_state.network`: `vpc`, `public_subnets_ids`, `private_subnets_ids`

## Provides
- `eks_cluster`, `cluster_name`, `node_group`, `cluster_iam_role_arn`, `node_iam_role_arn`

## Notes
- `var.api_access.public_access_cidrs` has no usable default and rejects `0.0.0.0/0`: the endpoint is public only because this lab has no VPN between the clouds (see the main README).
- Cost drivers: control plane hour rate + 2 x t3.large.
