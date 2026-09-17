output "admin_access_key_id" {
  value = aws_iam_access_key.admin.id
}

output "admin_secret_access_key" {
  value     = aws_iam_access_key.admin.secret
  sensitive = true
}

output "cluster_name" {
  value = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.main.endpoint
}

output "ecr_repository_url" {
  value = aws_ecr_repository.ai_memory.repository_url
}

output "backup_bucket" {
  value = aws_s3_bucket.backups.id
}

output "artifacts_bucket" {
  value = aws_s3_bucket.artifacts.id
}

output "instance_profile" {
  value = aws_iam_instance_profile.ai_host.name
}

output "cluster_ca" {
  value = aws_eks_cluster.main.certificate_authority[0].data
}
