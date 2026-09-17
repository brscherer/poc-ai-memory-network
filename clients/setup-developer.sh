#!/usr/bin/env bash
# One-time wiring of Claude Code to a team's shared ai-memory server.
# The LLM gateway itself is configured by managed-settings.json, so this
# script only handles memory.
#
#   AI_MEMORY_SERVER_URL=https://memory-team-a.example.com \
#   AI_MEMORY_USER=jdoe \
#   clients/setup-developer.sh
#
# The aim_ key is read from Secrets Manager so it never lands in shell
# history. Re-running is safe (install commands are idempotent).
set -euo pipefail
: "${AI_MEMORY_SERVER_URL:?}"; : "${AI_MEMORY_USER:?}"

command -v ai-memory >/dev/null || {
  echo "ai-memory CLI missing - install the pinned internal package first"; exit 1; }

AI_MEMORY_AUTH_TOKEN="$(aws secretsmanager get-secret-value \
  --secret-id "ai-memory/developers/${AI_MEMORY_USER}/api-key" \
  --query SecretString --output text)"

# Session-aware MCP: a local stdio bridge forwards Claude Code's session id,
# so agents never have to pass workspace/project by hand.
ai-memory install-mcp --client claude-code --session-aware \
  --server-url "$AI_MEMORY_SERVER_URL" --auth-token "$AI_MEMORY_AUTH_TOKEN" --apply

# Hooks:
#   --capture-mode allowlist  only repos with a committed .ai-memory.toml are captured
#   --project-strategy repo-root  worktrees/subdirs collapse into one project
# Attribution comes from the aim_ key's owner. (--as-user is only a label, and
# ai-memory 2.2.1 rejects it whenever the token is persisted to disk.)
ai-memory install-hooks --agent claude-code \
  --server-url "$AI_MEMORY_SERVER_URL" --auth-token "$AI_MEMORY_AUTH_TOKEN" \
  --capture-mode allowlist --project-strategy repo-root \
  ${AI_MEMORY_NO_PROMPTS:+--no-capture-prompts} \
  --apply

echo "done. Open Claude Code in a repo that has .ai-memory.toml and run /status."
