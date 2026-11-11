output "cluster_name" {
  description = "Regional ECS cluster name."
  value       = module.load_runner.cluster_name
}

output "log_group_name" {
  description = "Regional ECS task log group name."
  value       = module.load_runner.log_group_name
}

output "region" {
  description = "Region of this load runner."
  value       = module.load_runner.region
}

output "vpc_id" {
  description = "VPC the regional load generators run in."
  value       = module.load_runner.vpc_id
}
