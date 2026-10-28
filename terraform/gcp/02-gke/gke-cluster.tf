resource "google_container_cluster" "this" {
  name                = var.gke.cluster_name
  location            = var.gke.location
  network             = local.network_id
  subnetwork          = local.subnetwork_id
  networking_mode     = "VPC_NATIVE"
  datapath_provider   = var.gke.datapath_provider
  deletion_protection = var.gke.deletion_protection

  # No default node pool: since 1.36.4-gke.1469000 GKE creates the cluster
  # without one when initial_node_count and node_config are omitted
  # (remove_default_node_pool is deprecated). The pool is
  # google_container_node_pool.this, managed independently.

  ip_allocation_policy {
    cluster_secondary_range_name  = local.pods_range_name
    services_secondary_range_name = local.services_range_name
  }

  private_cluster_config {
    enable_private_nodes    = var.gke.enable_private_nodes
    enable_private_endpoint = var.gke.enable_private_endpoint
    master_ipv4_cidr_block  = var.gke.master_ipv4_cidr_block
  }

  # Public on purpose, and only for the two callers that need it: without a
  # VPN between the clouds, istiod in EKS reaches this API over the internet.
  master_authorized_networks_config {
    gcp_public_cidrs_access_enabled = false

    dynamic "cidr_blocks" {
      for_each = var.api_access.authorized_cidrs

      content {
        display_name = cidr_blocks.value.display_name
        cidr_block   = cidr_blocks.value.cidr_block
      }
    }
  }

  workload_identity_config {
    workload_pool = "${var.impersonation.project_id}.svc.id.goog"
  }

  release_channel {
    channel = var.gke.release_channel
  }
}
