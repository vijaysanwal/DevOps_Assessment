terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  backend "s3" {}
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project     = "devops-assessment"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

module "network" {
  source               = "../../modules/network"
  name                 = var.environment
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  single_nat_gateway   = var.single_nat_gateway
}

module "ecs" {
  source             = "../../modules/ecs"
  name               = var.environment
  vpc_id             = module.network.vpc_id
  public_subnet_ids  = module.network.public_subnet_ids
  private_subnet_ids = module.network.private_subnet_ids
  container_image    = var.container_image
  container_port     = 80
  task_cpu           = var.task_cpu
  task_memory        = var.task_memory
  desired_count      = var.desired_count
  health_check_path  = "/"
}

module "rds" {
  source                  = "../../modules/rds"
  name                    = var.environment
  vpc_id                  = module.network.vpc_id
  private_subnet_ids      = module.network.private_subnet_ids
  ecs_security_group_id   = module.ecs.ecs_security_group_id
  instance_class          = var.db_instance_class
  allocated_storage       = var.db_allocated_storage
  backup_retention_period = var.backup_retention_period
  deletion_protection     = var.deletion_protection
  db_name                 = var.db_name
  db_username             = var.db_username
  db_password             = var.db_password
}
