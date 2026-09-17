locals {
  # name -> generated value. The LiteLLM service key is filled in later by
  # 70-keys.sh (it can only be issued by LiteLLM itself), so it starts as a
  # placeholder and Tofu ignores changes to it.
  generated_secrets = {
    "ai-gateway/litellm/master-key"      = "sk-${random_password.litellm_master.result}"
    "ai-gateway/litellm/salt-key"        = random_password.litellm_salt.result
    "ai-gateway/litellm/db-password"     = random_password.litellm_db.result
    "ai-memory/${var.tenant}/root-token" = random_password.memory_root.result
    # Rotating the pepper invalidates every issued aim_ key.
    "ai-memory/${var.tenant}/token-pepper" = random_password.memory_pepper.result
    # Without this the server refuses to start once human users exist.
    "ai-memory/${var.tenant}/recovery-token" = random_password.memory_recovery.result
  }
}

resource "random_password" "litellm_master" {
  length  = 32
  special = false
}
resource "random_password" "litellm_salt" {
  length  = 32
  special = false
}
resource "random_password" "litellm_db" {
  length  = 24
  special = false
}
resource "random_password" "memory_root" {
  length  = 48
  special = false
}
resource "random_password" "memory_pepper" {
  length  = 48
  special = false
}
resource "random_password" "memory_recovery" {
  length  = 48
  special = false
}

resource "aws_secretsmanager_secret" "generated" {
  for_each                = local.generated_secrets
  name                    = each.key
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "generated" {
  for_each      = local.generated_secrets
  secret_id     = aws_secretsmanager_secret.generated[each.key].id
  secret_string = each.value
}

resource "aws_secretsmanager_secret" "litellm_service_key" {
  name                    = "ai-memory/${var.tenant}/litellm-key"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "litellm_service_key" {
  secret_id     = aws_secretsmanager_secret.litellm_service_key.id
  secret_string = "pending-bootstrap"
  lifecycle { ignore_changes = [secret_string] }
}

# Stand-in for EKS Pod Identity, which floci does not emulate: the in-cluster
# workloads sign AWS calls with the admin key. Not a production pattern.
resource "aws_secretsmanager_secret" "backup_aws" {
  name                    = "ai-memory/${var.tenant}/backup-aws"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "backup_aws" {
  secret_id = aws_secretsmanager_secret.backup_aws.id
  secret_string = jsonencode({
    access_key = aws_iam_access_key.admin.id
    secret_key = aws_iam_access_key.admin.secret
  })
}
