variable "tags" {
  description = "Global tags injected by the provider default_tags block. Resources only add Name (plus the discovery tags listed in the stack README)."
  type        = map(string)

  default = {
    "Project"   = "istio-p6"
    "Env"       = "lab"
    "region"    = "us-east-1"
    "ManagedBy" = "terraform"
  }
}

variable "assume_role" {
  description = "Region and optional role for the provider. The lab runs on the operator's credentials (AWS_PROFILE) with role_arn = null; set a role ARN to run through a delegated role."
  type = object({
    role_arn = string
    region   = string
  })

  default = {
    role_arn = null
    region   = "us-east-1"
  }
}

variable "remote_backend" {
  description = "Where the upstream stacks keep their state. bucket carries the account ID, so scripts/lib.sh sets it through TF_VAR_remote_backend."
  type = object({
    bucket = string
    region = string
  })

  default = {
    bucket = ""
    region = "us-east-1"
  }

  validation {
    condition     = var.remote_backend.bucket != ""
    error_message = "Set remote_backend.bucket (scripts/lib.sh exports TF_VAR_remote_backend)."
  }
}

variable "api_access" {
  description = "CIDRs allowed to reach the public EKS API endpoint: the operator running the lab and the GKE Cloud NAT address (istiod in GKE reads this API). scripts/lib.sh sets it through TF_VAR_api_access."
  type = object({
    public_access_cidrs = list(string)
  })

  default = {
    public_access_cidrs = []
  }

  validation {
    condition     = length(var.api_access.public_access_cidrs) > 0 && !contains(var.api_access.public_access_cidrs, "0.0.0.0/0")
    error_message = "The EKS endpoint must be allow-listed: at least one CIDR, never 0.0.0.0/0."
  }
}

variable "eks" {
  description = "Cluster, node group and access configuration. admin_principal_arn is the only IAM principal that gets Kubernetes cluster-admin; null means the identity running apply."
  type = object({
    cluster_name            = string
    cluster_version         = string
    cluster_iam_role_name   = string
    cluster_policy_arns     = list(string)
    node_iam_role_name      = string
    node_policy_arns        = list(string)
    authentication_mode     = string
    endpoint_public_access  = bool
    endpoint_private_access = bool
    admin_principal_arn     = string
    admin_access_policy_arn = string
    node_group = object({
      name           = string
      instance_types = list(string)
      ami_type       = string
      capacity_type  = string
      disk_size      = number
      desired_size   = number
      min_size       = number
      max_size       = number
    })
  })

  default = {
    cluster_name          = "eks-cluster-istio-p6"
    cluster_version       = "1.36"
    cluster_iam_role_name = "eks-cluster-iam-role-istio-p6"
    cluster_policy_arns = [
      "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy",
    ]
    node_iam_role_name = "eks-node-iam-role-istio-p6"
    node_policy_arns = [
      "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
      "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly",
      "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    ]
    authentication_mode     = "API"
    endpoint_public_access  = true
    endpoint_private_access = true
    admin_principal_arn     = null
    admin_access_policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
    node_group = {
      name = "eks-node-group-istio-p6"
      # Two vCPU and 8 GiB per node: istiod, the east-west gateway and the
      # sidecars of the lab services fit on two nodes.
      instance_types = ["t3.large"]
      ami_type       = "AL2023_x86_64_STANDARD"
      capacity_type  = "ON_DEMAND"
      disk_size      = 20
      desired_size   = 2
      min_size       = 1
      max_size       = 2
    }
  }
}
