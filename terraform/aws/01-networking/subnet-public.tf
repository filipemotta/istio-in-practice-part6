# Discovery tags: the EKS cloud provider places internet-facing load balancers
# (the east-west gateway) in subnets tagged kubernetes.io/role/elb.
resource "aws_subnet" "public" {
  count                   = length(var.vpc.public_subnets)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.vpc.public_subnets[count.index].cidr_block
  availability_zone       = var.vpc.public_subnets[count.index].availability_zone
  map_public_ip_on_launch = var.vpc.public_subnets[count.index].map_public_ip_on_launch

  tags = {
    Name                                                = var.vpc.public_subnets[count.index].name
    "kubernetes.io/role/elb"                            = "1"
    "kubernetes.io/cluster/${var.vpc.eks_cluster_name}" = "shared"
  }
}
