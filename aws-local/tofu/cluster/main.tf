# Pods cannot resolve Docker's embedded DNS, so the AWS APIs get a stable
# in-cluster name backed by floci's container IP.
resource "kubernetes_namespace" "aws_local" {
  metadata {
    name = "aws-local"
  }
}

resource "kubernetes_service" "aws" {
  metadata {
    name      = "aws"
    namespace = kubernetes_namespace.aws_local.metadata[0].name
  }
  spec {
    port {
      name        = "http"
      port        = 4566
      target_port = 4566
    }
  }
}

resource "kubernetes_endpoint_slice_v1" "aws" {
  metadata {
    name      = "aws-floci"
    namespace = kubernetes_namespace.aws_local.metadata[0].name
    labels = {
      "kubernetes.io/service-name" = kubernetes_service.aws.metadata[0].name
    }
  }
  address_type = "IPv4"
  port {
    name         = "http"
    port         = 4566
    app_protocol = "http"
  }
  endpoint {
    addresses = [var.aws_endpoint_ip]
  }
}

resource "kubernetes_namespace" "external_secrets" {
  metadata {
    name = "external-secrets"
  }
}

# Stand-in for EKS Pod Identity: static keys for the External Secrets
# controller, which 40-platform.sh installs by Helm.
resource "kubernetes_secret" "aws_credentials" {
  metadata {
    name      = "aws-credentials"
    namespace = kubernetes_namespace.external_secrets.metadata[0].name
  }
  data = {
    "access-key"        = var.aws_access_key_id
    "secret-access-key" = var.aws_secret_access_key
  }
}

# Namespaces the NetworkPolicy checks use: one allowed to reach ai-memory,
# one deliberately not labelled.
resource "kubernetes_namespace" "np_agents" {
  metadata {
    name   = "np-agents"
    labels = { "ai-platform/memory-client" = "true" }
  }
}

resource "kubernetes_namespace" "np_outsider" {
  metadata {
    name = "np-outsider"
  }
}
