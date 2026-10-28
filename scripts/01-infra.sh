#!/usr/bin/env bash
# shellcheck disable=SC2030,SC2031 # each parallel subshell sets its own TF_VAR_* on purpose
# Step 1: the two clouds. Terraform, stack by stack:
#   aws/00 + gcp/00  state buckets (local state)
#   aws/01 + gcp/01  networks; each NAT address is the source of every call
#                    that cloud makes to the other
#   aws/02 + gcp/02  clusters, each API endpoint allow-listed to the operator
#                    and to the other cloud's NAT address (in parallel)
# Then the lab kubeconfig (out/kubeconfig) with the contexts gke-p6 and eks-p6.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

step "state buckets"
for c in aws gcp; do
  tf_init "${c}" 00-remote-backend
  tf "${c}" 00-remote-backend apply -input=false -no-color -auto-approve | tail -1
done

step "networks"
remote_backend_vars "$(aws_state_bucket)" "${AWS_REGION}"
tf_init aws 01-networking
tf aws 01-networking apply -input=false -no-color -auto-approve | tail -1
remote_backend_vars "$(gcp_state_bucket)"
tf_init gcp 01-networking
tf gcp 01-networking apply -input=false -no-color -auto-approve | tail -1

AWS_NAT="$(tf aws 01-networking output -raw nat_public_ip)"
GCP_NAT="$(tf gcp 01-networking output -raw nat_public_ip)"
OPERATOR="$(operator_cidr)"
printf '%s\n' "${AWS_NAT}" > "${OUT}/aws-nat-ip"
printf '%s\n' "${GCP_NAT}" > "${OUT}/gcp-nat-ip"
note "AWS NAT gateway address: ${AWS_NAT}"
note "GCP Cloud NAT address:   ${GCP_NAT}"
note "operator:                ${OPERATOR}"

step "clusters (EKS and GKE in parallel)"
(
  remote_backend_vars "$(aws_state_bucket)" "${AWS_REGION}"
  export TF_VAR_api_access="{\"public_access_cidrs\":[\"${OPERATOR}\",\"${GCP_NAT}/32\"]}"
  tf_init aws 02-eks
  tf aws 02-eks apply -input=false -no-color -auto-approve > "${OUT}/apply-02-eks.log" 2>&1
) &
eks_pid=$!
(
  remote_backend_vars "$(gcp_state_bucket)"
  export TF_VAR_api_access="{\"authorized_cidrs\":[{\"display_name\":\"operator\",\"cidr_block\":\"${OPERATOR}\"},{\"display_name\":\"aws-nat\",\"cidr_block\":\"${AWS_NAT}/32\"}]}"
  tf_init gcp 02-gke
  tf gcp 02-gke apply -input=false -no-color -auto-approve > "${OUT}/apply-02-gke.log" 2>&1
) &
gke_pid=$!
rc=0
wait "${eks_pid}" || { rc=1; echo "aws/02-eks failed:"; tail -30 "${OUT}/apply-02-eks.log"; }
wait "${gke_pid}" || { rc=1; echo "gcp/02-gke failed:"; tail -30 "${OUT}/apply-02-gke.log"; }
[ "${rc}" -eq 0 ]
tail -1 "${OUT}/apply-02-eks.log"
tail -1 "${OUT}/apply-02-gke.log"

step "lab kubeconfig (${KUBECONFIG})"
rm -f "${KUBECONFIG}"
aws eks update-kubeconfig --region "${AWS_REGION}" --name "${EKS_CLUSTER}" --alias "${CTX_EKS}" --kubeconfig "${KUBECONFIG}" >/dev/null
# Name the cluster entries after the contexts (gke-p6, eks-p6): the cloud CLIs
# name them after ARNs and project paths.
eks_cluster_entry="$(kubectl config view -o jsonpath="{.contexts[?(@.name==\"${CTX_EKS}\")].context.cluster}")"
eks_server="$(kubectl config view -o jsonpath="{.clusters[?(@.name==\"${eks_cluster_entry}\")].cluster.server}")"
eks_ca="$(kubectl config view --raw -o jsonpath="{.clusters[?(@.name==\"${eks_cluster_entry}\")].cluster.certificate-authority-data}")"
kubectl config set-cluster "${CTX_EKS}" --server="${eks_server}" >/dev/null
kubectl config set "clusters.${CTX_EKS}.certificate-authority-data" "${eks_ca}" >/dev/null
kubectl config set-context "${CTX_EKS}" --cluster="${CTX_EKS}" >/dev/null
kubectl config delete-cluster "${eks_cluster_entry}" >/dev/null

gcloud container clusters get-credentials "${GKE_CLUSTER}" --zone "${GCP_ZONE}" >/dev/null 2>&1
gke_ctx="gke_${GCP_PROJECT}_${GCP_ZONE}_${GKE_CLUSTER}"
kubectl config rename-context "${gke_ctx}" "${CTX_GKE}" >/dev/null
gke_server="$(kubectl config view -o jsonpath="{.clusters[?(@.name==\"${gke_ctx}\")].cluster.server}")"
gke_ca="$(kubectl config view --raw -o jsonpath="{.clusters[?(@.name==\"${gke_ctx}\")].cluster.certificate-authority-data}")"
kubectl config set-cluster "${CTX_GKE}" --server="${gke_server}" >/dev/null
kubectl config set "clusters.${CTX_GKE}.certificate-authority-data" "${gke_ca}" >/dev/null
kubectl config set-context "${CTX_GKE}" --cluster="${CTX_GKE}" >/dev/null
kubectl config delete-cluster "${gke_ctx}" >/dev/null
assert_lab_context

step "checks"
expect_eq "kubeconfig has exactly the two lab contexts" "eks-p6 gke-p6" "$(kubectl config get-contexts -o name | sort | xargs)"
expect_eq "EKS nodes Ready" "2" "$(k_eks get nodes --no-headers | grep -c ' Ready ')"
expect_eq "GKE nodes Ready" "2" "$(k_gke get nodes --no-headers | grep -c ' Ready ')"
expect_eq "EKS runs Kubernetes 1.36" "1.36" "$(aws eks describe-cluster --region "${AWS_REGION}" --name "${EKS_CLUSTER}" --query cluster.version --output text)"
expect_match "GKE runs Kubernetes 1.36" '^1\.36\.' "$(gcloud container clusters describe "${GKE_CLUSTER}" --zone "${GCP_ZONE}" --format='value(currentMasterVersion)')"

eks_cidrs="$(aws eks describe-cluster --region "${AWS_REGION}" --name "${EKS_CLUSTER}" --query 'cluster.resourcesVpcConfig.publicAccessCidrs' --output text | tr '\t' '\n' | sort | xargs)"
expect_eq "EKS API allow-list is the operator and the GCP NAT address, nothing else" "$(printf '%s\n%s\n' "${OPERATOR}" "${GCP_NAT}/32" | sort | xargs)" "${eks_cidrs}"
gke_cidrs="$(gcloud container clusters describe "${GKE_CLUSTER}" --zone "${GCP_ZONE}" --format='value(masterAuthorizedNetworksConfig.cidrBlocks[].cidrBlock)' | tr ';' '\n' | sort | xargs)"
expect_eq "GKE API allow-list is the operator and the AWS NAT address, nothing else" "$(printf '%s\n%s\n' "${OPERATOR}" "${AWS_NAT}/32" | sort | xargs)" "${gke_cidrs}"
expect_eq "GKE does not open its API to Google Cloud public ranges" "False" "$(gcloud container clusters describe "${GKE_CLUSTER}" --zone "${GCP_ZONE}" --format='value(masterAuthorizedNetworksConfig.gcpPublicCidrsAccessEnabled)')"
expect_eq "GKE nodes have no public address" "True" "$(gcloud container clusters describe "${GKE_CLUSTER}" --zone "${GCP_ZONE}" --format='value(privateClusterConfig.enablePrivateNodes)')"
# shellcheck disable=SC2016 # backticks are JMESPath literals, not shell
expect_eq "EKS nodes run in private subnets (no public IP)" "0" "$(aws ec2 describe-instances --region "${AWS_REGION}" --filters "Name=tag:eks:cluster-name,Values=${EKS_CLUSTER}" "Name=instance-state-name,Values=running" --query 'length(Reservations[].Instances[?PublicIpAddress!=`null`][])' --output text)"
finish
