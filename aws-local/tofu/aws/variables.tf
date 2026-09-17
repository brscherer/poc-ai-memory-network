variable "region" {
  description = "AWS region."
  type        = string
  default     = "us-east-1"
}

variable "aws_endpoint" {
  description = "AWS API endpoint. floci locally; leave empty for real AWS."
  type        = string
  default     = "http://127.0.0.1:4566"
}

variable "tenant" {
  description = "ai-memory tenant (one instance per trust boundary)."
  type        = string
  default     = "team-a"
}

variable "cluster_name" {
  type    = string
  default = "ai-platform"
}

variable "backup_bucket" {
  type    = string
  default = "example-ai-memory-backups"
}

variable "artifacts_bucket" {
  type    = string
  default = "example-ai-platform-artifacts"
}

variable "ai_memory_version" {
  description = "ai-memory release whose tarballs are published to the artifact bucket."
  type        = string
  default     = "2.2.1"
}

variable "artifact_cache_dir" {
  description = "Local directory holding the downloaded release tarballs (10-artifacts.sh)."
  type        = string
  default     = "../../.state/cache"
}
