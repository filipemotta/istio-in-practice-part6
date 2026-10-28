#!/usr/bin/env bash
# Step 4: trust. The EKS intermediate CA is reissued from the GKE team's root,
# so both clusters now chain to one root. istiod and every proxy on EKS are
# restarted to pick the new CA up; the call from step 3 then goes through.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
assert_lab_context

step "reissue the EKS intermediate from the common root"
bash "${REPO_ROOT}/scripts/certs.sh" root-gke-team eks-us-east-1
d="${REPO_ROOT}/certs/root-gke-team/eks-us-east-1"
k eks -n istio-system create secret generic cacerts \
  --from-file="${d}/ca-cert.pem" --from-file="${d}/ca-key.pem" \
  --from-file="${d}/root-cert.pem" --from-file="${d}/cert-chain.pem" \
  --dry-run=client -o yaml | k eks apply -f - >/dev/null

step "restart istiod, then the proxies that hold certificates from the old CA"
k eks -n istio-system rollout restart deploy/istiod >/dev/null
k eks -n istio-system rollout status deploy/istiod --timeout=5m >/dev/null
k eks -n istio-system rollout restart deploy/istio-eastwestgateway >/dev/null
k eks -n payments rollout restart deploy/fraud-check >/dev/null
k eks -n istio-system rollout status deploy/istio-eastwestgateway --timeout=5m >/dev/null
k eks -n payments rollout status deploy/fraud-check --timeout=5m >/dev/null
sleep 15

step "checks"
gke_root="$(k gke -n istio-system get cm istio-ca-root-cert -o jsonpath='{.data.root-cert\.pem}' | openssl x509 -noout -fingerprint -sha256)"
eks_root="$(k eks -n istio-system get cm istio-ca-root-cert -o jsonpath='{.data.root-cert\.pem}' | openssl x509 -noout -fingerprint -sha256)"
expect_eq "both clusters now publish the same root" "${gke_root}" "${eks_root}"
eks_chain_root="$(ictl eks proxy-config secret deploy/fraud-check.payments -o json \
  | jq -r '.dynamicActiveSecrets[] | select(.name == "ROOTCA") | .secret.validationContext.trustedCa.inlineBytes' | base64 -d | openssl x509 -noout -fingerprint -sha256)"
expect_eq "the EKS fraud-check proxy trusts that root" "${gke_root}" "${eks_chain_root}"
fraud_calls 20 > "${OUT}/calls-04-common-root.txt"
cat "${OUT}/calls-04-common-root.txt" | awk '{ print $1, $2 }' | sort | uniq -c | sed 's/^/      /'
expect_eq "the same 20 calls now succeed, served by EKS" "20" "$(count_served "${OUT}/calls-04-common-root.txt" eks-us-east-1)"
note "median latency GKE -> EKS: $(median_ms "${OUT}/calls-04-common-root.txt" eks-us-east-1) ms"

step "bring the GKE fraud-check back"
k gke -n payments scale deploy/fraud-check --replicas=1 >/dev/null
k gke -n payments rollout status deploy/fraud-check --timeout=5m >/dev/null
finish
