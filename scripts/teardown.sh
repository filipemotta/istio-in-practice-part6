#!/usr/bin/env bash
# shellcheck disable=SC2030,SC2031 # each parallel subshell sets its own TF_VAR_* on purpose
# Destroys everything the lab created, in reverse order, then looks for what
# a cloud can leave behind after terraform destroy: load balancers created by
# Kubernetes Services, their firewall rules and target pools, network
# interfaces, disks. Exits non-zero if anything is left.
#
# KEEP_STATE_BUCKETS=1 keeps the two 00-remote-backend stacks (state buckets)
# between runs.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

step "Kubernetes load balancers first (the clouds created them, not Terraform)"
if [ -f "${KUBECONFIG}" ]; then
  for c in gke eks; do
    if k "${c}" get ns >/dev/null 2>&1; then
      k "${c}" get svc -A -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' \
        | while read -r ns name; do
            [ -n "${ns}" ] || continue
            note "${c}: deleting Service ${ns}/${name}"
            k "${c}" -n "${ns}" delete svc "${name}" --wait=true --timeout=5m
          done
    fi
  done
  # The cloud controllers delete the load balancers asynchronously.
  sleep 60
fi

# The account may hold other workloads: every AWS leftover check is scoped to
# the lab VPC, captured before it is destroyed.
LAB_VPC="$(aws ec2 describe-vpcs --region "${AWS_REGION}" --filters Name=tag:Project,Values=istio-p6 --query 'Vpcs[0].VpcId' --output text 2>/dev/null || true)"
note "lab VPC: ${LAB_VPC}"

step "clusters (in parallel)"
(
  remote_backend_vars "$(aws_state_bucket)" "${AWS_REGION}"
  export TF_VAR_api_access='{"public_access_cidrs":["127.0.0.1/32"]}'
  tf_init aws 02-eks
  tf aws 02-eks destroy -input=false -no-color -auto-approve > "${OUT}/destroy-02-eks.log" 2>&1
) &
eks_pid=$!
(
  remote_backend_vars "$(gcp_state_bucket)"
  export TF_VAR_api_access='{"authorized_cidrs":[{"display_name":"none","cidr_block":"127.0.0.1/32"}]}'
  tf_init gcp 02-gke
  tf gcp 02-gke destroy -input=false -no-color -auto-approve > "${OUT}/destroy-02-gke.log" 2>&1
) &
gke_pid=$!
rc=0
wait "${eks_pid}" || { rc=1; tail -30 "${OUT}/destroy-02-eks.log"; }
wait "${gke_pid}" || { rc=1; tail -30 "${OUT}/destroy-02-gke.log"; }
[ "${rc}" -eq 0 ]
tail -1 "${OUT}/destroy-02-eks.log"
tail -1 "${OUT}/destroy-02-gke.log"

step "networks"
remote_backend_vars "$(aws_state_bucket)" "${AWS_REGION}"
tf_init aws 01-networking
tf aws 01-networking destroy -input=false -no-color -auto-approve | tail -1
remote_backend_vars "$(gcp_state_bucket)"
tf_init gcp 01-networking
tf gcp 01-networking destroy -input=false -no-color -auto-approve | tail -1

if [ "${KEEP_STATE_BUCKETS:-0}" != 1 ]; then
  step "state buckets"
  for c in aws gcp; do
    tf_init "${c}" 00-remote-backend
    tf "${c}" 00-remote-backend destroy -input=false -no-color -auto-approve | tail -1
  done
fi
rm -f "${KUBECONFIG}"

step "leftovers"
# shellcheck disable=SC2016 # backticks are JMESPath literals, not shell
expect_eq "AWS: no network/application load balancers in the lab VPC" "0" \
  "$(aws elbv2 describe-load-balancers --region "${AWS_REGION}" --query "length(LoadBalancers[?VpcId=='${LAB_VPC}'])" --output text)"
expect_eq "AWS: no classic load balancers in the lab VPC" "0" \
  "$(aws elb describe-load-balancers --region "${AWS_REGION}" --query "length(LoadBalancerDescriptions[?VPCId=='${LAB_VPC}'])" --output text)"
expect_eq "AWS: no lab VPC left" "0" \
  "$(aws ec2 describe-vpcs --region "${AWS_REGION}" --filters Name=tag:Project,Values=istio-p6 --query 'length(Vpcs)' --output text)"
expect_eq "AWS: no lab network interfaces left" "0" \
  "$(aws ec2 describe-network-interfaces --region "${AWS_REGION}" --filters "Name=vpc-id,Values=${LAB_VPC}" --query 'length(NetworkInterfaces)' --output text)"
expect_eq "AWS: no lab volumes left" "0" \
  "$(aws ec2 describe-volumes --region "${AWS_REGION}" --filters "Name=tag:eks:cluster-name,Values=${EKS_CLUSTER}" --query 'length(Volumes)' --output text)"
expect_eq "AWS: no unattached Elastic IPs tagged for the lab" "0" \
  "$(aws ec2 describe-addresses --region "${AWS_REGION}" --filters Name=tag:Project,Values=istio-p6 --query 'length(Addresses)' --output text)"
expect_eq "GCP: no forwarding rules (load balancers)" "0" "$(gcloud compute forwarding-rules list --format='value(name)' | wc -l | tr -d ' ')"
expect_eq "GCP: no target pools" "0" "$(gcloud compute target-pools list --format='value(name)' | wc -l | tr -d ' ')"
expect_eq "GCP: no firewall rules left in lab networks" "0" "$(gcloud compute firewall-rules list --filter='network~istio-p6' --format='value(name)' | wc -l | tr -d ' ')"
expect_eq "GCP: no disks" "0" "$(gcloud compute disks list --format='value(name)' | wc -l | tr -d ' ')"
expect_eq "GCP: no reserved addresses" "0" "$(gcloud compute addresses list --format='value(name)' | wc -l | tr -d ' ')"
finish
