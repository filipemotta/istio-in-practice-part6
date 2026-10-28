#!/usr/bin/env bash
# Step 3: discovery. Each istiod gets a remote secret to read the other
# cluster's API, and the same namespace + Service on both sides becomes one
# service with endpoints in two clouds. The roots are still different, so a
# call that lands on the other cloud is refused at the TLS handshake.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
assert_lab_context

step "apps: payments-api + fraud-check on GKE, fraud-check on EKS (same namespace)"
k gke apply -f "${REPO_ROOT}/apps/payments-gke.yaml" >/dev/null
k eks apply -f "${REPO_ROOT}/apps/payments-eks.yaml" >/dev/null
k gke -n payments rollout status deploy/payments-api --timeout=5m >/dev/null
k gke -n payments rollout status deploy/fraud-check --timeout=5m >/dev/null
k eks -n payments rollout status deploy/fraud-check --timeout=5m >/dev/null

step "remote secrets: each istiod reads the other cluster's API"
ictl gke create-remote-secret --name=gke-us-east4 | k eks apply -f - >/dev/null
ictl eks create-remote-secret --name=eks-us-east-1 | k gke apply -f - >/dev/null
for _ in $(seq 1 30); do
  g="$(ictl gke remote-clusters 2>/dev/null | awk '$1 == "eks-us-east-1" { print $3 }')"
  e="$(ictl eks remote-clusters 2>/dev/null | awk '$1 == "gke-us-east4" { print $3 }')"
  [ "${g}" = synced ] && [ "${e}" = synced ] && break
  sleep 5
done
ictl gke remote-clusters
ictl eks remote-clusters

step "checks"
expect_eq "istiod on GKE has synced the EKS cluster" "synced" "${g:-}"
expect_eq "istiod on EKS has synced the GKE cluster" "synced" "${e:-}"
expect_eq "the reader account the other istiod uses cannot create pods" "no" \
  "$(k gke auth can-i create pods --as=system:serviceaccount:istio-system:istio-reader-service-account -n payments 2>/dev/null || true)"
# The price of the agreement: the reader role Istio installs for remote
# secrets can read every Secret in every namespace of this cluster, and the
# other cluster's istiod holds a token for it.
expect_eq "but it can read Secrets, in any namespace (kube-system included)" "yes" \
  "$(k gke auth can-i get secrets --as=system:serviceaccount:istio-system:istio-reader-service-account -n kube-system 2>/dev/null || true)"

fraud_eps() {
  ictl gke proxy-config endpoint deploy/payments-api.payments --cluster 'outbound|8080||fraud-check.payments.svc.cluster.local' -o json \
    | jq -r '.[].hostStatuses[] | .address.socketAddress | "\(.address):\(.portValue)"' | sort
}
# Wait until the GKE proxy reaches EKS through the gateway. Until istiod on
# GKE knows the EKS network and its gateway address, it can publish the EKS
# pod IP itself, which nothing in Google Cloud can reach. The first answer is
# kept: it is the evidence of what a caller sees in that window.
eps="$(fraud_eps)"
printf '%s\n' "${eps}" > "${OUT}/endpoints-03-first.txt"
waited=0
until grep -q ':15443$' <<< "${eps}" && [ "$(grep -c ':8080$' <<< "${eps}")" = 1 ]; do
  [ "${waited}" -ge 600 ] && break
  sleep 10; waited=$((waited + 10))
  eps="$(fraud_eps)"
done
note "first view of fraud-check endpoints in payments-api's proxy:"
sed 's/^/      /' "${OUT}/endpoints-03-first.txt"
note "after ${waited}s:"
printf '%s\n' "${eps}" | sed 's/^/      /'
expect_eq "one local endpoint (pod IP, port 8080)" "1" "$(grep -c ':8080$' <<< "${eps}")"
expect_ge "the EKS fraud-check appears as the EKS east-west gateway on 15443" 1 "$(grep -c ':15443$' <<< "${eps}")"

step "wait for the EKS gateway to accept connections from GKE"
# A new Network Load Balancer answers only once its targets pass the health
# check. Until then a connection hangs (curl exit 28); afterwards the gateway
# accepts TCP and resets a TLS hello without a mesh SNI (35 or 56).
eks_addr="$(cat "${OUT}/eastwest-eks-address")"
waited=0
while :; do
  rc=0
  k_gke -n payments exec deploy/payments-api -c app -- curl -sk --connect-timeout 5 -o /dev/null "https://${eks_addr}:15443/" >/dev/null 2>&1 || rc=$?
  case "${rc}" in 35|56) break ;; esac
  [ "${waited}" -ge 600 ] && break
  sleep 10; waited=$((waited + 10))
done
note "EKS gateway reachable after ${waited}s (curl exit ${rc})"

step "a call that lands on EKS, while the roots differ"
k gke -n payments scale deploy/fraud-check --replicas=0 >/dev/null
k gke -n payments wait --for=delete pod -l app=fraud-check --timeout=2m >/dev/null 2>&1 || true
sleep 10
fraud_calls 10 > "${OUT}/calls-03-different-roots.txt"
sort "${OUT}/calls-03-different-roots.txt" | uniq -c | sed 's/^/      /'
# Most fail fast with 503; right after the local pod goes away an attempt can
# still hang to the 5 s client timeout (000). None may succeed.
expect_eq "no call to EKS succeeds while the roots differ" "0" "$(count_code "${OUT}/calls-03-different-roots.txt" 200)"
expect_ge "the caller gets 503 from its own proxy" 1 "$(count_code "${OUT}/calls-03-different-roots.txt" 503)"
body="$(k_gke -n payments exec deploy/payments-api -c app -- curl -s --max-time 5 http://fraud-check.payments:8080/ || true)"
note "body: ${body}"
# The body only says "remote connection failure". The reason is in the
# caller's proxy at debug level for the connection logger (Part 4).
ictl gke proxy-config log deploy/payments-api.payments --level connection:debug >/dev/null
k_gke -n payments exec deploy/payments-api -c app -- curl -s -o /dev/null --max-time 5 http://fraud-check.payments:8080/ || true
sleep 3
reason="$(k gke -n payments logs deploy/payments-api -c istio-proxy --since=20s | grep -o 'CERTIFICATE_VERIFY_FAILED:verify cert failed:[^:]*: certificate verification error at depth [0-9]*: [a-z ]*' | head -1)"
ictl gke proxy-config log deploy/payments-api.payments --level connection:warning >/dev/null
note "caller proxy: ${reason}"
expect_match "the caller's proxy rejects the EKS certificate chain" 'CERTIFICATE_VERIFY_FAILED.*self signed certificate in certificate chain' "${reason}"
finish
