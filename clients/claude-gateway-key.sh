#!/usr/bin/env bash
# apiKeyHelper for Claude Code: print the caller's LiteLLM virtual key and
# nothing else. Keys live in AWS Secrets Manager under
#   ai-gateway/developers/<username>/litellm
# and are readable only by that user's SSO permission set (or, on EC2/EKS,
# by the instance / pod role). Install as /usr/local/bin/claude-gateway-key.
set -euo pipefail
USER_ID="${AI_GATEWAY_USER:-$(id -un)}"
exec aws secretsmanager get-secret-value \
  --secret-id "ai-gateway/developers/${USER_ID}/litellm" \
  --query SecretString --output text 2>/dev/null
