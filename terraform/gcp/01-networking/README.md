# gcp/01-networking

## Purpose
The Google Cloud network of the lab: custom VPC, one subnet in us-east4 with secondary ranges for GKE, Cloud Router and Cloud NAT on a reserved address.

## Provisions
- `google_compute_network.main`, `google_compute_subnetwork.this` (`10.20.0.0/20`; pods `10.21.0.0/16`, services `10.22.0.0/20`)
- `google_compute_router.this`
- `google_compute_address.nat` + `google_compute_router_nat.this` (`MANUAL_ONLY`)

## Consumes
- nothing

## Provides
- `network`, `subnetwork`, `pods_range_name`, `services_range_name`, `router`, `nat`
- `nat_public_ip`: the source address of every call GKE makes to EKS. `scripts/01-infra.sh` puts it on the EKS API allow-list, and `scripts/02-istio.sh` on the EKS east-west load balancer.

## Notes
- A reserved address instead of `AUTO_ONLY`: an automatic NAT address can change, and the EKS side allow-lists it.
