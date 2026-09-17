output "vpc_id" {
  description = "ID of the private VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "Validated RFC1918 CIDR assigned to the VPC."
  value       = aws_vpc.this.cidr_block
}

output "private_subnet_ids" {
  description = "IDs of the two private subnets."
  value       = aws_subnet.private[*].id
}

output "private_subnet_cidrs" {
  description = "CIDRs derived for the two private subnets."
  value       = aws_subnet.private[*].cidr_block
}

output "private_subnet_availability_zones" {
  description = "Sydney availability zones used by the two private subnets."
  value       = aws_subnet.private[*].availability_zone
}

output "private_route_table_id" {
  description = "ID of the route table associated with both private subnets."
  value       = aws_route_table.private.id
}

output "s3_gateway_endpoint_id" {
  description = "ID of the S3 Gateway VPC endpoint."
  value       = aws_vpc_endpoint.s3.id
}
