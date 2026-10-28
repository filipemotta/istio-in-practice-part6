#!/usr/bin/env bash
# Step 7: what is public, and who can reach it. Without a VPN the east-west
# gateways have public addresses, so each load balancer must accept only the
# other cloud's NAT address. Checked from the operator's machine (refused)
# and from inside the mesh (used by every cross-cloud call above).
set -euo pipefail
source "$(dirname "$0")/lib.sh"
assert_lab_context

step "from this machine (not on any allow-list of the gateways)"
for c in gke eks; do
  addr="$(cat "${OUT}/eastwest-${c}-address")"
  set +e
  curl -sk --connect-timeout 8 -o /dev/null "https://${addr}:15443/"
  rc=$?
  set -e
  note "${c} east-west ${addr}:15443 -> curl exit ${rc}"
  # 28 = connect timeout (dropped), 7 = refused. 35 or 0 would mean the TLS
  # port answered.
  expect_match "${c}: the east-west gateway does not answer outsiders" '^(7|28)$' "${rc}"
done

step "from GKE, through Cloud NAT, to the EKS gateway"
eks_addr="$(cat "${OUT}/eastwest-eks-address")"
set +e
k_gke -n payments exec deploy/payments-api -c app -- curl -sk --connect-timeout 8 -o /dev/null "https://${eks_addr}:15443/"
rc=$?
set -e
note "curl exit ${rc}"
# The gateway only forwards mTLS with a mesh SNI, so a bare TLS hello is
# reset (35/56) after the TCP connection is accepted: reachable, not open.
expect_match "the GKE NAT address reaches the EKS gateway, which still refuses a non-mesh client" '^(35|56)$' "${rc}"
finish
