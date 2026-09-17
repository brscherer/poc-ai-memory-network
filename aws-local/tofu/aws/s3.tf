resource "aws_s3_bucket" "backups" {
  bucket        = var.backup_bucket
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "backups" {
  bucket = aws_s3_bucket.backups.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Private artifact store: the release tarballs EC2 hosts install from.
resource "aws_s3_bucket" "artifacts" {
  bucket        = var.artifacts_bucket
  force_destroy = true
}

resource "aws_s3_object" "ai_memory_release" {
  for_each = toset(["aarch64", "x86_64"])
  bucket   = aws_s3_bucket.artifacts.id
  key      = "ai-memory/${var.ai_memory_version}/ai-memory-linux-${each.key}.tar.gz"
  source   = "${var.artifact_cache_dir}/ai-memory-linux-${each.key}.tar.gz"
  etag     = filemd5("${var.artifact_cache_dir}/ai-memory-linux-${each.key}.tar.gz")
}
