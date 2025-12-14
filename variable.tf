# VPC and Subnet Variables
variable "vpc_cidr" {
  description = "Primary VPC CIDR block"
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of Availability Zones (subnets per tier)"
  type        = number
  default     = 2
}

variable "public_subnets" {
  description = "Optional list of public subnet CIDRs"
  default     = []
}

variable "private_subnets" {
  description = "Optional list of private (app) subnet CIDRs"
  default     = []
}

variable "db_subnets" {
  description = "Optional list of DB subnet CIDRs"
  default     = []
}

# Project info
variable "project_name" {
  description = "Project name"
  default     = "three-tier-vpc"
}

variable "aws_region" {
  description = "AWS region"
  default     = "ap-southeast-1"
}

# EC2
variable "ami" {
  description = "AMI ID for EC2 instances"
  default     = "ami-0c56f26c1d3277bcb"
}

variable "instance_type" {
  description = "EC2 instance type"
  default     = "t2.micro"
}

# RDS
variable "db_instance_type" {
  description = "RDS instance type"
  default     = "db.t3.micro"
}

variable "db_username" {
  description = "DB username"
  default     = "root"
}

variable "db_password" {
  description = "DB password"
  default     = "rohan9027"
}

# ALB options
variable "enable_alb" {
  description = "Enable public ALB"
  type        = bool
  default     = true
}

variable "enable_internal_alb" {
  description = "Enable internal ALB"
  type        = bool
  default     = true
}

# Local subnet computation
locals {
  az_count = var.az_count

  # Compute /24 subnets from /16 VPC
  computed_public_subnets  = [for i in range(local.az_count) : cidrsubnet(var.vpc_cidr, 8, i)]
  computed_private_subnets = [for i in range(local.az_count) : cidrsubnet(var.vpc_cidr, 8, i + local.az_count)]
  computed_db_subnets      = [for i in range(local.az_count) : cidrsubnet(var.vpc_cidr, 8, i + local.az_count * 2)]

  public_subnet_cidrs  = length(var.public_subnets) > 0 ? var.public_subnets : local.computed_public_subnets
  private_subnet_cidrs = length(var.private_subnets) > 0 ? var.private_subnets : local.computed_private_subnets
  db_subnet_cidrs      = length(var.db_subnets) > 0 ? var.db_subnets : local.computed_db_subnets
}