output "vpc" {
  description = "The VPC object. Consumed by 02-eks."
  value       = aws_vpc.main
}

output "internet_gateway" {
  description = "The internet gateway object."
  value       = aws_internet_gateway.this
}

output "nat_gateway" {
  description = "The NAT gateway object."
  value       = aws_nat_gateway.this
}

output "public_subnets_ids" {
  description = "IDs of the public subnets, in AZ order. Consumed by 02-eks (cluster endpoint ENIs)."
  value       = aws_subnet.public[*].id
}

output "private_subnets_ids" {
  description = "IDs of the private subnets, in AZ order. Consumed by 02-eks (node group)."
  value       = aws_subnet.private[*].id
}

output "public_subnet_arn" {
  description = "ARNs of the public subnets."
  value       = aws_subnet.public[*].arn
}

output "private_subnet_arn" {
  description = "ARNs of the private subnets."
  value       = aws_subnet.private[*].arn
}

output "nat_public_ip" {
  description = "Public IP of the NAT gateway: the source address of every call EKS makes to GKE (API server and east-west gateway)."
  value       = aws_eip.this.public_ip
}
