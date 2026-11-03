aws_region             = "ap-south-1"
availability_zones    = ["ap-south-1a", "ap-south-1b"]
environment            = "prod"
vpc_cidr               = "10.20.0.0/16"
public_subnet_cidrs    = ["10.20.1.0/24", "10.20.2.0/24"]
private_subnet_cidrs   = ["10.20.11.0/24", "10.20.12.0/24"]
single_nat_gateway     = false
container_image        = "nginx:1.27-alpine"
task_cpu               = 1024
task_memory            = 2048
desired_count          = 3
db_instance_class      = "db.t4g.medium"
db_allocated_storage   = 100
backup_retention_period = 14
deletion_protection    = true
db_name                = "appdb"
db_username            = "appadmin"
# Supply db_password securely with TF_VAR_db_password; do not commit secrets.
