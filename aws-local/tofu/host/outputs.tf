output "instance_id" {
  value = aws_instance.host.id
}

output "host_name" {
  value = var.host_name
}
