#!/usr/bin/env bash
# Step 2: one istiod per cloud (multi-primary), each on its own network, each
# with an east-west gateway. Each cluster starts with its OWN root CA, the way
# two teams usually arrive with their own clusters: step 4 fixes that.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
bash "${REPO_ROOT}/tools/install-cli.sh" >/dev/null
assert_lab_context

AWS_NAT="$(cat "${OUT}/aws-nat-ip")"
GCP_NAT="$(cat "${OUT}/gcp-nat-ip")"

# cluster -> network, peer NAT, root CA
declare -A NETWORK=([gke]=network-gcp [eks]=network-aws)
declare -A PEER_CIDR=([gke]="${AWS_NAT}/32" [eks]="${GCP_NAT}/32")
declare -A CLUSTER_NAME=([gke]=gke-us-east4 [eks]=eks-us-east-1)
declare -A ROOT=([gke]=root-gke-team [eks]=root-eks-team)

for c in gke eks; do
  step "${c}: plugin CA from ${ROOT[${c}]}, network label, istiod"
  bash "${REPO_ROOT}/scripts/certs.sh" "${ROOT[${c}]}" "${CLUSTER_NAME[${c}]}"
  d="${REPO_ROOT}/certs/${ROOT[${c}]}/${CLUSTER_NAME[${c}]}"
  k "${c}" create namespace istio-system --dry-run=client -o yaml | k "${c}" apply -f - >/dev/null
  k "${c}" label namespace istio-system "topology.istio.io/network=${NETWORK[${c}]}" --overwrite >/dev/null
  k "${c}" -n istio-system create secret generic cacerts \
    --from-file="${d}/ca-cert.pem" --from-file="${d}/ca-key.pem" \
    --from-file="${d}/root-cert.pem" --from-file="${d}/cert-chain.pem" \
    --dry-run=client -o yaml | k "${c}" apply -f - >/dev/null
  ictl "${c}" install -y -f "${REPO_ROOT}/istio/${c}.yaml" 2>&1 | tail -2

  step "${c}: east-west gateway (accepts only ${PEER_CIDR[${c}]})"
  sed -e "s|@NETWORK@|${NETWORK[${c}]}|g" -e "s|@PEER_CIDR@|${PEER_CIDR[${c}]}|" \
    "${REPO_ROOT}/istio/eastwest-gateway.yaml" > "${OUT}/eastwest-${c}.yaml"
  if [ "${c}" = eks ]; then
    # A Network Load Balancer (TCP passthrough) instead of the Classic default.
    sed -i.bak 's|serviceAnnotations: {}|serviceAnnotations: {service.beta.kubernetes.io/aws-load-balancer-type: nlb}|' "${OUT}/eastwest-${c}.yaml"
  fi
  ictl "${c}" install -y -f "${OUT}/eastwest-${c}.yaml" 2>&1 | tail -2
  k "${c}" -n istio-system apply -f "${REPO_ROOT}/istio/expose-services.yaml" >/dev/null
done

step "waiting for the east-west load balancers"
for c in gke eks; do
  for _ in $(seq 1 60); do
    addr="$(k "${c}" -n istio-system get svc istio-eastwestgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}{.status.loadBalancer.ingress[0].hostname}')"
    [ -n "${addr}" ] && break
    sleep 10
  done
  printf '%s\n' "${addr}" > "${OUT}/eastwest-${c}-address"
  note "${c}: ${addr}"
done

step "checks"
for c in gke eks; do
  expect_eq "${c}: istiod Available" "True" "$(k "${c}" -n istio-system get deploy istiod -o jsonpath='{.status.conditions[?(@.type=="Available")].status}')"
  expect_eq "${c}: istiod runs ${ISTIO_VERSION}" "${ISTIO_VERSION}" "$(k "${c}" -n istio-system get deploy istiod -o jsonpath='{.spec.template.spec.containers[0].image}' | sed 's/.*://')"
  expect_eq "${c}: istio-system carries its network label" "${NETWORK[${c}]}" "$(k "${c}" get ns istio-system -o jsonpath='{.metadata.labels.topology\.istio\.io/network}')"
  expect_eq "${c}: east-west gateway Available" "True" "$(k "${c}" -n istio-system get deploy istio-eastwestgateway -o jsonpath='{.status.conditions[?(@.type=="Available")].status}')"
  expect_match "${c}: east-west gateway has a public address" '.+' "$(cat "${OUT}/eastwest-${c}-address")"
  expect_eq "${c}: east-west load balancer accepts only the peer NAT address" "${PEER_CIDR[${c}]}" "$(k "${c}" -n istio-system get svc istio-eastwestgateway -o jsonpath='{.spec.loadBalancerSourceRanges[*]}')"
  # Without this variable the gateway would also forward to endpoints of the
  # other network: a call could cross clouds twice and come back.
  expect_eq "${c}: east-west gateway only forwards inside its own network" "${NETWORK[${c}]}" "$(k "${c}" -n istio-system get deploy istio-eastwestgateway -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="ISTIO_META_REQUESTED_NETWORK_VIEW")].value}')"
  expect_eq "${c}: east-west gateway exposes only 15021 and 15443" "15021 15443" "$(k "${c}" -n istio-system get svc istio-eastwestgateway -o jsonpath='{.spec.ports[*].port}')"
  expect_eq "${c}: cross-network Gateway is AUTO_PASSTHROUGH on 15443" "AUTO_PASSTHROUGH 15443" "$(k "${c}" -n istio-system get gateway.networking.istio.io cross-network-gateway -o jsonpath='{.spec.servers[0].tls.mode} {.spec.servers[0].port.number}')"
done
gke_root="$(k gke -n istio-system get cm istio-ca-root-cert -o jsonpath='{.data.root-cert\.pem}' | openssl x509 -noout -fingerprint -sha256)"
eks_root="$(k eks -n istio-system get cm istio-ca-root-cert -o jsonpath='{.data.root-cert\.pem}' | openssl x509 -noout -fingerprint -sha256)"
if [ "${gke_root}" != "${eks_root}" ]; then pass "the two clusters start with different roots (one per team)"; else fail "the two clusters start with different roots"; fi
finish
