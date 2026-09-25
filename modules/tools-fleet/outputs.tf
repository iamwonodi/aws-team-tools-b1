output "auto_scaling_group_name" {
  description = "The tools' Auto Scaling group: the Start tools workflow sets its desired capacity."
  value       = aws_autoscaling_group.this.name
}

output "addresses" {
  description = "The tools' web addresses, behind the front door. Empty where there is none (production: use the tunnel)."
  value       = local.front_door ? { for tool in keys(local.tools) : tool => "https://${tool}.${local.domain_name}" } : {}
}

output "connections" {
  description = "The databases the tools are prepared for: engine, host, port and whether TLS is verified."
  value       = local.connections
}

output "schedule" {
  description = "When the tools run on their own, Lagos time."
  value       = "${var.schedule_days}, ${var.schedule_start_hour}:00-${var.schedule_stop_hour}:00"
}
