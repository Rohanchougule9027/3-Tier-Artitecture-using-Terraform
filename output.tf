// Outputs for three-tier architecture
output "Public_ip" {
  description = "Public IP of the EC2 instance"
  value       = aws_instance.public_server.public_ip
}


output "Private_ip" {
  value       = aws_instance.private_app_server.private_ip
  description = "Private IP of app tier instance"
}

output "VPC_CIDR" {
  value       = var.vpc_cidr
  description = "VPC CIDR block"
}

output "Public_Subnet_CIDRs" {
  value       = local.public_subnet_cidrs
  description = "Public subnet CIDRs"
}

output "Private_Subnet_CIDRs" {
  value       = local.private_subnet_cidrs
  description = "Private subnet CIDRs"
}

output "DB_Subnet_CIDRs" {
  value       = local.db_subnet_cidrs
  description = "Database subnet CIDRs"
}