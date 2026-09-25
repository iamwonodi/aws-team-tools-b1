output "auto_scaling_group_name" {
  description = "The tools' Auto Scaling group."
  value       = module.tools.auto_scaling_group_name
}

output "addresses" {
  description = "The tools' web addresses (none in production: use the tunnel)."
  value       = module.tools.addresses
}

output "connections" {
  description = "The databases the tools are prepared for."
  value       = module.tools.connections
}

output "schedule" {
  description = "When the tools run on their own, Lagos time."
  value       = module.tools.schedule
}
