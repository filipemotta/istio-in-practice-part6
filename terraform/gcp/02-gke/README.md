# gcp/02-gke

## Purpose
Zonal GKE Standard (us-east4-a, release channel REGULAR, 1.36) with private nodes and a public endpoint allow-listed to two addresses: the operator and the AWS NAT gateway address (istiod on EKS reads this API).

## Provisions
- `google_container_cluster.this` (VPC-native, Dataplane V2, Workload Identity, no default node pool, `master_authorized_networks_config` from `var.api_access`, Google Cloud public ranges off)
- `google_container_node_pool.this` (2 x e2-standard-2)
- `google_service_account.node` + `google_project_iam_member.node[*]` (logging, monitoring, Artifact Registry read)
- `google_compute_firewall.istio_webhook`: control plane range to the nodes on 15017, where istiod serves its admission webhooks

## Consumes
- `01-networking` via `data.terraform_remote_state.network`: `network`, `subnetwork`, `pods_range_name`, `services_range_name`

## Provides
- `gke_cluster` (sensitive), `cluster_name`, `node_pool`, `node_service_account_email`

## Notes
- `var.api_access.authorized_cidrs` has no usable default and rejects `0.0.0.0/0`.
- `deletion_protection = false` is a lab value.
- Cost drivers: cluster management fee (covered by the GKE free tier credit for one zonal cluster per billing account) + 2 x e2-standard-2.
