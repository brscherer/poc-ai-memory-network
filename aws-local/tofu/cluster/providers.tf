# Applied after tofu/aws, authenticating the way a person does: `aws eks
# get-token` against the cluster, with the endpoint and CA the first stack
# produced.
#
# Everything here is a short API call on purpose. floci accepts an EKS token
# for 60 seconds, and a provider resolves its credentials once per apply, so
# anything that waits minutes (a Helm install with --wait) outlives its own
# token. Those installs run from the CLI in 40-platform.sh instead.
locals {
  exec_env = {
    AWS_ENDPOINT_URL      = var.aws_endpoint
    AWS_ACCESS_KEY_ID     = var.aws_access_key_id
    AWS_SECRET_ACCESS_KEY = var.aws_secret_access_key
    AWS_DEFAULT_REGION    = var.region
  }
  exec_args = ["eks", "get-token", "--cluster-name", var.cluster_name, "--output", "json"]
}

provider "kubernetes" {
  host                   = var.cluster_endpoint
  cluster_ca_certificate = base64decode(var.cluster_ca)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = local.exec_args
    env         = local.exec_env
  }
}
