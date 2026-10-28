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

variable "vpc" {
  description = "Network layout. Subnets are ordered lists consumed with count; index i of public and private share an AZ."
  type = object({
    name                     = string
    cidr_block               = string
    enable_dns_support       = bool
    enable_dns_hostnames     = bool
    internet_gateway_name    = string
    nat_gateway_name         = string
    public_route_table_name  = string
    eks_cluster_name         = string
    private_route_table_name = string
    public_subnets = list(object({
      name                    = string
      cidr_block              = string
      availability_zone       = string
      map_public_ip_on_launch = bool
    }))
    private_subnets = list(object({
      name              = string
      cidr_block        = string
      availability_zone = string
    }))
  })

  default = {
    name                     = "vpc-istio-p6-useast1"
    cidr_block               = "10.10.0.0/16"
    enable_dns_support       = true
    enable_dns_hostnames     = true
    internet_gateway_name    = "igw-istio-p6-useast1"
    nat_gateway_name         = "nat-gateway-istio-p6-useast1"
    public_route_table_name  = "public-route-table-istio-p6-useast1"
    eks_cluster_name         = "eks-cluster-istio-p6"
    private_route_table_name = "private-route-table-istio-p6-useast1"
    public_subnets = [
      {
        name                    = "public-subnet-istio-p6-useast1a"
        cidr_block              = "10.10.0.0/24"
        availability_zone       = "us-east-1a"
        map_public_ip_on_launch = true
      },
      {
        name                    = "public-subnet-istio-p6-useast1b"
        cidr_block              = "10.10.1.0/24"
        availability_zone       = "us-east-1b"
        map_public_ip_on_launch = true
      },
    ]
    private_subnets = [
      {
        name              = "private-subnet-istio-p6-useast1a"
        cidr_block        = "10.10.10.0/24"
        availability_zone = "us-east-1a"
      },
      {
        name              = "private-subnet-istio-p6-useast1b"
        cidr_block        = "10.10.11.0/24"
        availability_zone = "us-east-1b"
      },
    ]
  }
}
