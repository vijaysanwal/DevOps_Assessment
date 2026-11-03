aws_region             = "ap-south-1"
availability_zones    = ["ap-south-1a", "ap-south-1b"]
environment            = "dev"
vpc_cidr               = "10.10.0.0/16"
public_subnet_cidrs    = ["10.10.1.0/24", "10.10.2.0/24"]
private_subnet_cidrs   = ["10.10.11.0/24", "10.10.12.0/24"]
single_nat_gateway     = true
container_image        = "nginx:1.27-alpine"
task_cpu               = 256
task_memory            = 512
desired_count          = 1
db_instance_class      = "db.t4g.micro"
db_allocated_storage   = 20
backup_retention_period = 1
deletion_protection    = false
db_name                = "appdb"
db_username            = "appadmin"
# Supply db_password securely with TF_VAR_db_password; do not commit secrets.
