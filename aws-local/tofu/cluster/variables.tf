variable "cluster_name" {
  type    = string
  default = "ai-platform"
}

variable "cluster_endpoint" {
  description = "EKS API endpoint (output of tofu/aws)."
  type        = string
  default     = ""
}

variable "cluster_ca" {
  description = "Base64 cluster CA (output of tofu/aws)."
  type        = string
  default     = ""
}

variable "aws_endpoint" {
  description = "AWS API endpoint used by `aws eks get-token`."
  type        = string
  default     = "http://127.0.0.1:4566"
}

variable "aws_endpoint_ip" {
  description = "floci's address on the Docker network; reached by pods through the aws Service."
  type        = string
  default     = "127.0.0.1"
}

variable "aws_access_key_id" {
  description = "Stand-in for EKS Pod Identity: static keys for the ESO controller."
  type        = string
  sensitive   = true
  default     = ""
}

variable "aws_secret_access_key" {
  type      = string
  sensitive = true
  default   = ""
}

variable "region" {
  type    = string
  default = "us-east-1"
}
