# Private nodes accept from the control plane only the ports GKE opens by
# default. istiod serves its admission webhooks (sidecar injection and
# config validation) on 15017, so the control plane range needs this rule.
resource "google_compute_firewall" "istio_webhook" {
  name    = var.gke.istio_webhook_firewall_name
  network = local.network_id

  direction     = "INGRESS"
  source_ranges = [var.gke.master_ipv4_cidr_block]

  allow {
    protocol = "tcp"
    ports    = ["15017"]
  }

  target_service_accounts = [google_service_account.node.email]
}
