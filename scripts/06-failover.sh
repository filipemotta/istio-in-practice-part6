#!/usr/bin/env bash
# Step 6: failover across clouds. The GKE fraud-check starts answering 503.
# With the default maxEjectionPercent nothing moves; with 100%, outlier
# detection ejects the local pod and the calls move to EKS. The repair is a
# rollout, so the repaired pod is a new endpoint and the calls come back to it.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
assert_lab_context
N=200
ARGS_OK='["server","-http-port","8080","-grpc-port","disabled","-redirect-port","disabled","-tcp-port","disabled","-udp-port","disabled","-echo-server-default-params","header=x-served-by:gke-us-east4"]'
ARGS_503='["server","-http-port","8080","-grpc-port","disabled","-redirect-port","disabled","-tcp-port","disabled","-udp-port","disabled","-echo-server-default-params","header=x-served-by:gke-us-east4&status=503"]'

local_failed() {
  ictl gke proxy-config endpoint deploy/payments-api.payments --cluster 'outbound|8080||fraud-check.payments.svc.cluster.local' -o json \
    | jq -r '[.[].hostStatuses[] | select(.address.socketAddress.portValue == 8080) | .healthStatus.failedOutlierCheck // false] | join(",")'
}

step "break the GKE fraud-check (every answer 503), default maxEjectionPercent"
k gke apply -f "${REPO_ROOT}/mesh/failover-default-ejection.yaml" >/dev/null
k gke -n payments patch deploy fraud-check --type=json -p "[{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/args\",\"value\":${ARGS_503}}]" >/dev/null
k gke -n payments rollout status deploy/fraud-check --timeout=5m >/dev/null
sleep 10
fraud_calls 50 > "${OUT}/calls-06-default-ejection.txt"
errs="$(count_code "${OUT}/calls-06-default-ejection.txt" 503)"
note "503 seen by the caller: ${errs} of 50"
expect_eq "with the default 10% the caller keeps getting the local 503s" "50" "${errs}"
expect_eq "and the local endpoint is never ejected" "false" "$(local_failed)"

step "same failure, maxEjectionPercent: 100"
k gke apply -f "${REPO_ROOT}/mesh/locality-failover.yaml" >/dev/null
sleep 10
fraud_calls "${N}" > "${OUT}/calls-06-failover.txt"
eks_n="$(count_served "${OUT}/calls-06-failover.txt" eks-us-east-1)"
errs="$(count_code "${OUT}/calls-06-failover.txt" 503)"
note "served by EKS: ${eks_n}, 503 seen by the caller: ${errs}"
expect_ge "the calls fail over to EKS" $((N - 5)) "${eks_n}"
expect_ge "calls without a 503 (at most 5 failed before the ejection)" "$((N - 5))" "$((N - errs))"
expect_eq "the local endpoint is marked as failed by outlier detection" "true" "$(local_failed)"

step "repair it (a rollout: the repaired pod is a new, un-ejected endpoint)"
k gke -n payments patch deploy fraud-check --type=json -p "[{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/args\",\"value\":${ARGS_OK}}]" >/dev/null
k gke -n payments rollout status deploy/fraud-check --timeout=5m >/dev/null
sleep 70 # let the old endpoint leave EDS in the caller's proxy
fraud_calls "${N}" > "${OUT}/calls-06-back.txt"
gke_n="$(count_served "${OUT}/calls-06-back.txt" gke-us-east4)"
note "served by GKE: ${gke_n}"
expect_eq "the calls are back in us-east4" "${N}" "${gke_n}"
finish
