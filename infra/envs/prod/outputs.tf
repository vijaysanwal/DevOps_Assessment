output "alb_dns_name" { value = module.ecs.alb_dns_name }
output "rds_endpoint" {
  value       = module.rds.endpoint
  description = "Private RDS endpoint; reachable from the ECS security group only."
}
