output "aws_service_url" {
  description = "In-cluster URL of the emulated AWS endpoint."
  value       = "http://${kubernetes_service.aws.metadata[0].name}.${kubernetes_namespace.aws_local.metadata[0].name}.svc.cluster.local:4566"
}
