# aws/01-networking

## Purpose
The AWS network of the lab: VPC `10.10.0.0/16`, two AZs, public and private subnets, one NAT gateway.

## Provisions
- `aws_vpc.main`, `aws_internet_gateway.this`
- `aws_subnet.public[*]`, `aws_subnet.private[*]`, the route tables and their associations
- `aws_eip.this` + `aws_nat_gateway.this` (single NAT: lab cost)

## Consumes
- nothing

## Provides
- `vpc`, `public_subnets_ids`, `private_subnets_ids`, `nat_gateway`
- `nat_public_ip`: the source address of every call EKS makes to GKE. `scripts/01-infra.sh` puts it on the GKE API allow-list, and `scripts/02-istio.sh` on the GKE east-west load balancer.

## Notes
- Discovery tags (beyond `Name`): `kubernetes.io/role/elb` on public subnets and `kubernetes.io/role/internal-elb` on private subnets, plus `kubernetes.io/cluster/eks-cluster-istio-p6 = shared`. The EKS cloud provider uses them to place the east-west gateway's Network Load Balancer.
