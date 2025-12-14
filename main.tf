terraform {
backend "s3" {
  bucket = "terraform-backend-6186"
  key    = "jumpserver"
  region = "ap-south-1"
}
}
provider "aws" {
  region = var.aws_region
}

# Availability Zones
data "aws_availability_zones" "available" {
  state = "available"
}

# VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = var.project_name
  }
}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = { Name = "${var.project_name}-igw" }
}

# Public Subnets
resource "aws_subnet" "public" {
  count                   = local.az_count
  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = { Name = "public-subnet-${count.index + 1}" }
}

# Private App Subnets
resource "aws_subnet" "private_app" {
  count             = local.az_count
  vpc_id            = aws_vpc.main.id
  cidr_block        = local.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = { Name = "private-app-subnet-${count.index + 1}" }
}

# Private DB Subnets
resource "aws_subnet" "private_db" {
  count             = local.az_count
  vpc_id            = aws_vpc.main.id
  cidr_block        = local.db_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = { Name = "private-db-subnet-${count.index + 1}" }
}

# Security Group for EC2 and RDS
resource "aws_security_group" "main_sg" {
  vpc_id      = aws_vpc.main.id
  name        = "${var.project_name}-sg"
  description = "Allow HTTP, SSH, MySQL traffic"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = local.private_subnet_cidrs
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-sg" }
}

# EC2 Instances
resource "aws_instance" "public_server" {
  ami                    = var.ami
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.main_sg.id]

  tags = { Name = "${var.project_name}-public" }
}

resource "aws_instance" "private_app_server" {
  ami                    = var.ami
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private_app[0].id
  vpc_security_group_ids = [aws_security_group.main_sg.id]

  tags = { Name = "${var.project_name}-app" }
}

resource "aws_instance" "private_web_server" {
  ami                    = var.ami
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private_app[0].id
  vpc_security_group_ids = [aws_security_group.main_sg.id]

  tags = { Name = "${var.project_name}-web" }
}

# RDS Subnet Group
resource "aws_db_subnet_group" "db_subnet" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = aws_subnet.private_db[*].id
  tags       = { Name = "${var.project_name}-db-subnet" }
}

# RDS Instance
resource "aws_db_instance" "mydb" {
  identifier             = "mydb-instance"
  allocated_storage      = 10
  db_name                = "mydb"
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = var.db_instance_type
  username               = var.db_username
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.db_subnet.name
  vpc_security_group_ids = [aws_security_group.main_sg.id]
  publicly_accessible    = false
  skip_final_snapshot    = true

  depends_on = [aws_subnet.private_db]
  tags       = { Name = "${var.project_name}-rds" }
}

# Public ALB
resource "aws_lb" "app_alb" {
  count               = var.enable_alb ? 1 : 0
  name                = "${var.project_name}-alb"
  internal            = false
  load_balancer_type  = "application"
  security_groups     = [aws_security_group.main_sg.id]
  subnets             = aws_subnet.public[*].id
}

resource "aws_lb_target_group" "app_tg" {
  count   = var.enable_alb ? 1 : 0
  name    = "${var.project_name}-tg"
  port    = 80
  protocol = "HTTP"
  vpc_id  = aws_vpc.main.id

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener" "app_listener" {
  count               = var.enable_alb ? 1 : 0
  load_balancer_arn   = aws_lb.app_alb[0].arn
  port                = 80
  protocol            = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg[0].arn
  }
}

resource "aws_lb_target_group_attachment" "attach_public_instance" {
  count             = var.enable_alb ? 1 : 0
  target_group_arn  = aws_lb_target_group.app_tg[0].arn
  target_id         = aws_instance.public_server.id
  port              = 80
}

# Internal ALB
resource "aws_lb" "internal_alb" {
  count               = var.enable_internal_alb ? 1 : 0
  name                = "${var.project_name}-internal-alb"
  internal            = true
  load_balancer_type  = "application"
  security_groups     = [aws_security_group.main_sg.id]
  subnets             = aws_subnet.private_app[*].id
}

resource "aws_lb_target_group" "internal_tg" {
  count    = var.enable_internal_alb ? 1 : 0
  name     = "${var.project_name}-internal-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check { path = "/" }
}

resource "aws_lb_listener" "internal_listener" {
  count               = var.enable_internal_alb ? 1 : 0
  load_balancer_arn   = aws_lb.internal_alb[0].arn
  port                = 80
  protocol            = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.internal_tg[0].arn
  }
}

resource "aws_lb_target_group_attachment" "internal_attach" {
  count            = var.enable_internal_alb ? 1 : 0
  target_group_arn = aws_lb_target_group.internal_tg[0].arn
  target_id        = aws_instance.private_app_server.id
  port             = 80
}

# create s3 bucket with enabled versioning
/*resource "aws_s3_bucket" "mybucket" {
  bucket = "terraform-bucket-9027"

  tags = {
    Name = "terraform-backend-bucket"
  }
}

resource "aws_s3_bucket_versioning" "versioning_example" {
  bucket = aws_s3_bucket.mybucket.bucket

  versioning_configuration {
    status = "Enabled"
  }
}*/