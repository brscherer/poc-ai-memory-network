# Applied last: the guest talks to the gateway and to ai-memory at boot, so
# both workloads and its credentials must already exist.
data "aws_iam_instance_profile" "ai_host" {
  name = "ai-host"
}

resource "aws_instance" "host" {
  ami                  = var.ami
  instance_type        = var.instance_type
  iam_instance_profile = data.aws_iam_instance_profile.ai_host.name

  user_data = templatefile("${path.module}/../../ec2/user-data.sh.tftpl", {
    host_name         = var.host_name
    gateway_url       = var.gateway_url
    memory_url        = var.memory_url
    ai_memory_version = var.ai_memory_version
    artifacts_bucket  = var.artifacts_bucket
  })

  tags = { Name = var.host_name }
}
