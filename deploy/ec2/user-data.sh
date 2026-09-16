#!/usr/bin/env bash
# EC2 user-data for development / agent hosts (Amazon Linux 2023).
# The instance role may read ONLY:
#   ai-gateway/hosts/<Name tag>/litellm      (LiteLLM virtual key)
#   ai-memory/hosts/<Name tag>/api-key       (ai-memory aim_ key)
# The host reaches LiteLLM and ai-memory through their internal ALBs.
set -euo pipefail

GATEWAY_URL="https://llm-gateway.example.com"
MEMORY_URL="https://memory-team-a.example.com"
RUN_AS="ec2-user"
ARTIFACTS="https://artifacts.example.com/ai-platform"

TOKEN=$(curl -sX PUT http://169.254.169.254/latest/api/token -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
NAME=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/tags/instance/Name)

# 1. Pinned, scanned binaries from a private artifact store.
curl -fsSL "$ARTIFACTS/ai-memory/2.2.1/ai-memory-linux-x86_64" -o /usr/local/bin/ai-memory
chmod 0755 /usr/local/bin/ai-memory
# (Claude Code is installed from the internal npm mirror / package here.)

# 2. Gateway key helper + managed settings (users cannot override).
cat > /usr/local/bin/claude-gateway-key <<SH
#!/bin/sh
exec aws secretsmanager get-secret-value --secret-id "ai-gateway/hosts/${NAME}/litellm" --query SecretString --output text
SH
chmod 0755 /usr/local/bin/claude-gateway-key
mkdir -p /etc/claude-code
cat > /etc/claude-code/managed-settings.json <<JSON
{
  "apiKeyHelper": "/usr/local/bin/claude-gateway-key",
  "env": {
    "ANTHROPIC_BASE_URL": "${GATEWAY_URL}",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "claude-opus-5",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "claude-sonnet-5",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "claude-haiku-4-5",
    "AI_MEMORY_SERVER_URL": "${MEMORY_URL}"
  }
}
JSON

# 3. Wire memory for the host's user.
MEM_KEY=$(aws secretsmanager get-secret-value --secret-id "ai-memory/hosts/${NAME}/api-key" --query SecretString --output text)
sudo -u "$RUN_AS" -H ai-memory install-hooks --agent claude-code --apply \
  --server-url "$MEMORY_URL" --auth-token "$MEM_KEY" --as-user "host-${NAME}" \
  --capture-mode allowlist --project-strategy repo-root
sudo -u "$RUN_AS" -H ai-memory install-mcp --client claude-code --session-aware --apply \
  --server-url "$MEMORY_URL" --auth-token "$MEM_KEY"
unset MEM_KEY
