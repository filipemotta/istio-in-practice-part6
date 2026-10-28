# A reserved address instead of AUTO_ONLY: EKS allow-lists the source of the
# calls GKE makes (istiod reading the EKS API, sidecars reaching the EKS
# east-west gateway), and an automatic address can change.
resource "google_compute_address" "nat" {
  name   = var.vpc.nat_address
  region = var.impersonation.region
}

resource "google_compute_router_nat" "this" {
  name                               = var.vpc.nat_name
  router                             = google_compute_router.this.name
  region                             = google_compute_router.this.region
  nat_ip_allocate_option             = "MANUAL_ONLY"
  nat_ips                            = [google_compute_address.nat.self_link]
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = var.vpc.nat_log_filter
  }
}
