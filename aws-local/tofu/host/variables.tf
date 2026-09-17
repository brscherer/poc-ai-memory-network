variable "region" {
  type    = string
  default = "us-east-1"
}

variable "aws_endpoint" {
  type    = string
  default = "http://127.0.0.1:4566"
}

variable "host_name" {
  description = "Name tag and identity prefix for the guest."
  type        = string
  default     = "ec2-dev-1"
}

# floci maps AMI ids to container images; an emulated guest of the wrong
# architecture is slow enough that its IMDS setup times out.
variable "ami" {
  type    = string
  default = "ami-ubuntu2404-arm64"
}

variable "instance_type" {
  type    = string
  default = "t4g.medium"
}

variable "ai_memory_version" {
  type    = string
  default = "2.2.1"
}

variable "artifacts_bucket" {
  type    = string
  default = "example-ai-platform-artifacts"
}

variable "gateway_url" {
  description = "LiteLLM, reached through the cluster NodePort (ALB stand-in)."
  type        = string
  default     = "http://floci-eks-ai-platform:30400"
}

variable "memory_url" {
  description = "ai-memory, reached through the cluster NodePort (ALB stand-in)."
  type        = string
  default     = "http://floci-eks-ai-platform:30374"
}
