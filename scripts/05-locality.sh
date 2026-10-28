#!/usr/bin/env bash
# Step 5: where the traffic goes. With the agreement in place, Istio spreads
# fraud-check calls over both clouds: the local pod and the remote cluster
# carry the same total weight (the remote one split over the gateway's
# addresses). A failover rule without outlier detection still sends calls
# across; with outlier detection, calls stay in us-east4.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
assert_lab_context
N=200

k gke -n payments delete destinationrule fraud-check --ignore-not-found >/dev/null
sleep 5

step "default: no DestinationRule (${N} calls from GKE)"
fraud_calls "${N}" > "${OUT}/calls-05-default.txt"
gke_n="$(count_served "${OUT}/calls-05-default.txt" gke-us-east4)"
eks_n="$(count_served "${OUT}/calls-05-default.txt" eks-us-east-1)"
note "served by GKE: ${gke_n}, by EKS: ${eks_n}"
note "median latency: GKE $(median_ms "${OUT}/calls-05-default.txt" gke-us-east4) ms, EKS $(median_ms "${OUT}/calls-05-default.txt" eks-us-east-1) ms"
expect_eq "every call succeeds" "${N}" "$((gke_n + eks_n))"
expect_ge "a large share crosses to the other cloud" $((N / 4)) "${eks_n}"
expect_ge "and a large share stays" $((N / 4)) "${gke_n}"
weights="$(ictl gke proxy-config endpoint deploy/payments-api.payments --cluster 'outbound|8080||fraud-check.payments.svc.cluster.local' -o json \
  | jq -r '[.[].hostStatuses[] | "\(.address.socketAddress.portValue):\(.weight)"] | sort | join(" ")')"
note "endpoint port:weight in the proxy: ${weights}"
expect_eq "local pod and EKS gateway addresses carry the same total weight" "$(jq -n --arg w "${weights}" '$w | split(" ") | map(split(":")) | (map(select(.[0]=="8080") | .[1] | tonumber) | add) == (map(select(.[0]=="15443") | .[1] | tonumber) | add)')" "true"

step "pitfall: locality failover without outlier detection"
warn="$(k gke apply -f "${REPO_ROOT}/mesh/locality-without-outlier.yaml" 2>&1 >/dev/null || true)"
note "kubectl apply said: ${warn}"
expect_match "istiod accepts the rule and only warns" 'outlier detection policy must be provided for failover' "${warn}"
sleep 10
fraud_calls "${N}" > "${OUT}/calls-05-no-outlier.txt"
gke_n="$(count_served "${OUT}/calls-05-no-outlier.txt" gke-us-east4)"
eks_n="$(count_served "${OUT}/calls-05-no-outlier.txt" eks-us-east-1)"
note "served by GKE: ${gke_n}, by EKS: ${eks_n}"
expect_ge "calls still cross to the other cloud" $((N / 8)) "${eks_n}"

step "locality failover with outlier detection"
k gke apply -f "${REPO_ROOT}/mesh/locality-failover.yaml" >/dev/null
sleep 10
fraud_calls "${N}" > "${OUT}/calls-05-locality.txt"
gke_n="$(count_served "${OUT}/calls-05-locality.txt" gke-us-east4)"
eks_n="$(count_served "${OUT}/calls-05-locality.txt" eks-us-east-1)"
note "served by GKE: ${gke_n}, by EKS: ${eks_n}"
expect_eq "every call stays in us-east4" "${N}" "${gke_n}"
prio="$(ictl gke proxy-config endpoint deploy/payments-api.payments --cluster 'outbound|8080||fraud-check.payments.svc.cluster.local' -o json \
  | jq -r '[.[].hostStatuses[] | "\(.address.socketAddress.portValue):\(.priority // 0)"] | sort | unique | join(" ")')"
note "endpoint port:priority in the proxy: ${prio}"
expect_match "local endpoint priority 0, the EKS gateway a lower priority" '^15443:[1-9][0-9]* 8080:0$' "${prio}"
finish
