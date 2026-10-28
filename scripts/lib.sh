#!/usr/bin/env bash
# Shared helpers sourced by the lab scripts. Not meant to be run directly.
# shellcheck shell=bash

# Decimal point, not comma, whatever the operator's locale: awk parses timings.
export LC_ALL=C

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${REPO_ROOT}/out"
mkdir -p "${OUT}"
export REPO_ROOT OUT
export PATH="${REPO_ROOT}/bin:${PATH}"

# --- what the lab runs on ----------------------------------------------------
# Both are required and never defaulted: the lab creates billable resources,
# so it only runs where you point it.
: "${AWS_PROFILE:?export AWS_PROFILE=<profile of the AWS account to use>}"
: "${GCP_PROJECT:?export GCP_PROJECT=<ID of the Google Cloud project to use>}"
export AWS_PROFILE GCP_PROJECT
# Optional: the Google account gcloud should use (when several are logged in).
if [ -n "${GCP_ACCOUNT:-}" ]; then export CLOUDSDK_CORE_ACCOUNT="${GCP_ACCOUNT}"; fi
# Every gcloud call goes to this project, whatever the gcloud default is.
export CLOUDSDK_CORE_PROJECT="${GCP_PROJECT}"

AWS_REGION="us-east-1"
GCP_REGION="us-east4"
GCP_ZONE="us-east4-a"
EKS_CLUSTER="eks-cluster-istio-p6"
GKE_CLUSTER="gke-cluster-istio-p6"
ISTIO_VERSION="1.31.3"
export AWS_REGION GCP_REGION GCP_ZONE EKS_CLUSTER GKE_CLUSTER ISTIO_VERSION

# The lab has its own kubeconfig with exactly two contexts. Your
# ~/.kube/config is never read or written.
export KUBECONFIG="${OUT}/kubeconfig"
CTX_GKE="gke-p6"
CTX_EKS="eks-p6"
export CTX_GKE CTX_EKS

k_gke() { kubectl --context "${CTX_GKE}" "$@"; }
k_eks() { kubectl --context "${CTX_EKS}" "$@"; }
# k <gke|eks> ...
k() { local c="$1"; shift; if [ "${c}" = gke ]; then k_gke "$@"; else k_eks "$@"; fi; }
ictl() { local c="$1"; shift; if [ "${c}" = gke ]; then istioctl --context "${CTX_GKE}" "$@"; else istioctl --context "${CTX_EKS}" "$@"; fi; }

# Safety: refuse to run unless both lab contexts exist in the lab kubeconfig
# and point at the two clusters this lab created (by API server address, read
# from the cloud APIs, not from the kubeconfig).
assert_lab_context() {
  local eks_server gke_server got_eks got_gke
  eks_server="$(aws eks describe-cluster --region "${AWS_REGION}" --name "${EKS_CLUSTER}" --query cluster.endpoint --output text 2>/dev/null || true)"
  gke_server="https://$(gcloud container clusters describe "${GKE_CLUSTER}" --zone "${GCP_ZONE}" --format='value(endpoint)' 2>/dev/null || true)"
  got_eks="$(kubectl config view -o jsonpath="{.clusters[?(@.name==\"${CTX_EKS}\")].cluster.server}" 2>/dev/null || true)"
  got_gke="$(kubectl config view -o jsonpath="{.clusters[?(@.name==\"${CTX_GKE}\")].cluster.server}" 2>/dev/null || true)"
  if [ -z "${eks_server}" ] || [ "${eks_server}" = "None" ] || [ "${got_eks}" != "${eks_server}" ] \
     || [ "${gke_server}" = "https://" ] || [ "${got_gke}" != "${gke_server}" ]; then
    echo "refusing to run: lab contexts do not match the lab clusters (eks: '${got_eks}' vs '${eks_server}', gke: '${got_gke}' vs '${gke_server}')" >&2
    exit 3
  fi
}

# --- terraform ---------------------------------------------------------------
# Terraform's google provider and gcs backend read GOOGLE_OAUTH_ACCESS_TOKEN.
# A token from gcloud lasts about an hour, so it is refreshed before each call.
gcp_token() { GOOGLE_OAUTH_ACCESS_TOKEN="$(gcloud auth print-access-token)"; export GOOGLE_OAUTH_ACCESS_TOKEN; }
aws_account() { aws sts get-caller-identity --query Account --output text; }
aws_state_bucket() { printf 'istio-p6-%s-useast1-tfstate' "$(aws_account)"; }
gcp_state_bucket() { printf '%s-tfstate' "${GCP_PROJECT}"; }

# tf <aws|gcp> <stack> <terraform args...>
tf() {
  local cloud="$1" stack="$2"; shift 2
  local dir="${REPO_ROOT}/terraform/${cloud}/${stack}"
  gcp_token
  export TF_IN_AUTOMATION=1
  if [ "${cloud}" = gcp ]; then
    TF_VAR_impersonation="$(jq -cn --arg p "${GCP_PROJECT}" --arg r "${GCP_REGION}" '{project_id: $p, region: $r, service_account: null}')"
    export TF_VAR_impersonation
  fi
  if [ "${stack}" = 00-remote-backend ]; then
    # 00 has its own remote_backend variable (the bucket it creates), with
    # another shape than the one 01 and 02 read from the environment.
    (unset TF_VAR_remote_backend; terraform -chdir="${dir}" "$@")
  else
    terraform -chdir="${dir}" "$@"
  fi
}
# tf_init <aws|gcp> <stack>: 00 keeps local state; the others use the bucket.
tf_init() {
  local cloud="$1" stack="$2" bucket
  if [ "${stack}" = 00-remote-backend ]; then
    tf "${cloud}" "${stack}" init -input=false -no-color >/dev/null
    return
  fi
  if [ "${cloud}" = aws ]; then bucket="$(aws_state_bucket)"; else bucket="$(gcp_state_bucket)"; fi
  tf "${cloud}" "${stack}" init -input=false -no-color -reconfigure -backend-config="bucket=${bucket}" >/dev/null
}
remote_backend_vars() {
  if [ -n "${2:-}" ]; then
    TF_VAR_remote_backend="$(jq -cn --arg b "$1" --arg r "$2" '{bucket: $b, region: $r}')"
  else
    TF_VAR_remote_backend="$(jq -cn --arg b "$1" '{bucket: $b}')"
  fi
  export TF_VAR_remote_backend
}
operator_cidr() { printf '%s/32' "$(curl -sSf https://checkip.amazonaws.com | tr -d '[:space:]')"; }

# --- output ------------------------------------------------------------------
step() { printf '\n==> %s\n' "$*"; }
note() { printf '    %s\n' "$*"; }

PASSED=0
FAILED=0
pass() { PASSED=$((PASSED + 1)); printf '    [PASS] %s\n' "$1"; }
fail() { FAILED=$((FAILED + 1)); printf '    [FAIL] %s\n' "$1"; }
# expect_eq <description> <expected> <actual>
expect_eq() {
  if [ "$2" = "$3" ]; then pass "$1 (got $3)"; else fail "$1 (expected $2, got $3)"; fi
}
# expect_match <description> <extended regex> <actual>
expect_match() {
  if grep -Eq -- "$2" <<< "$3"; then pass "$1"; else fail "$1 (no match for /$2/ in: $3)"; fi
}
# expect_ge <description> <minimum> <actual>
expect_ge() {
  if [ "$3" -ge "$2" ]; then pass "$1 (got $3, minimum $2)"; else fail "$1 (got $3, minimum $2)"; fi
}
finish() {
  printf '\n    result: %s passed, %s failed\n' "${PASSED}" "${FAILED}"
  [ "${FAILED}" -eq 0 ]
}

# --- the probe ---------------------------------------------------------------
# fraud_calls <n>: n sequential requests from payments-api (GKE) to
# fraud-check, one line each: "<http code> <x-served-by or -> <seconds>".
fraud_calls() {
  # shellcheck disable=SC2016 # the script runs in the pod's sh, which expands it
  k_gke -n payments exec deploy/payments-api -c app -- sh -c '
    i=0
    while [ "$i" -lt "$1" ]; do
      curl -s -o /dev/null -D - -w "time=%{time_total}\n" --max-time 5 http://fraud-check.payments:8080/ 2>/dev/null \
        | tr -d "\r" \
        | awk "NR==1 { c = \$2 } tolower(\$1) == \"x-served-by:\" { s = \$2 } /^time=/ { t = substr(\$0, 6) } END { print (c ? c : \"000\"), (s ? s : \"-\"), (t ? t : 0) }"
      i=$((i + 1))
    done' sh "$1"
}
# count_served <file> <cluster name>
count_served() { awk -v s="$2" '$1 == 200 && $2 == s' "$1" | wc -l | tr -d ' '; }
count_code() { awk -v c="$2" '$1 == c' "$1" | wc -l | tr -d ' '; }
# median_ms <file> <cluster name>: median total time of the requests it served
median_ms() {
  awk -v s="$2" '$1 == 200 && $2 == s { print $3 * 1000 }' "$1" | sort -n \
    | awk '{ a[NR] = $1 } END { if (NR == 0) { print 0 } else { printf "%d", a[int((NR + 1) / 2)] } }'
}
