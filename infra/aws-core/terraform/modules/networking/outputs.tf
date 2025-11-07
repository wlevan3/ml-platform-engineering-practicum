# ===================================================================
# Networking Module - Outputs
# ===================================================================

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = module.vpc.vpc_cidr_block
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = module.vpc.private_subnets
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = module.vpc.public_subnets
}

output "private_subnet_cidrs" {
  description = "CIDR blocks of the private subnets"
  value       = module.vpc.private_subnets_cidr_blocks
}

output "public_subnet_cidrs" {
  description = "CIDR blocks of the public subnets"
  value       = module.vpc.public_subnets_cidr_blocks
}

output "nat_gateway_ids" {
  description = "IDs of the NAT gateways"
  value       = module.vpc.natgw_ids
}

output "azs" {
  description = "Availability zones used"
  value       = module.vpc.azs
}

output "vpc_name" {
  description = "Name of the VPC"
  value       = module.vpc.name
}
