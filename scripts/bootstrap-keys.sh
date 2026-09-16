#!/usr/bin/env bash
# Issue the credentials the local POC needs, mirroring the shared-server provisioning flow:
#
#   1. LiteLLM team + virtual key for the ai-memory SERVICE (consolidation).
#   2. LiteLLM virtual key for one DEVELOPER (Claude Code inference).
#   3. ai-memory human user + native aim_ API key for that developer.
#
# Usage: scripts/bootstrap-keys.sh <username> <email> [team]
# Secrets are printed once. On a shared deployment, write them straight
# into AWS Secrets Manager instead of the terminal.
set -euo pipefail
cd "$(dirname "$0")/../local"
set -a; . ./.env; set +a

USERNAME="${1:?username}"
EMAIL="${2:?email}"
TEAM="${3:-team-a}"
LITELLM=http://127.0.0.1:4000
AUTH=(-H "Authorization: Bearer ${LITELLM_MASTER_KEY}" -H "Content-Type: application/json")

echo "== LiteLLM team '${TEAM}'"
TEAM_ID=$(curl -fsS "${AUTH[@]}" "$LITELLM/team/new" \
  -d "{\"team_alias\":\"${TEAM}\",\"models\":[\"claude-opus-5\",\"claude-sonnet-5\",\"claude-haiku-4-5\"]}" \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["team_id"])')
echo "team_id=${TEAM_ID}"

if [ -z "${AI_MEMORY_LITELLM_KEY:-}" ]; then
  echo "== LiteLLM service key for ai-memory"
  SVC_KEY=$(curl -fsS "${AUTH[@]}" "$LITELLM/key/generate" \
    -d '{"key_alias":"svc-ai-memory","models":["memory-consolidation","memory-embeddings"],"max_budget":50,"budget_duration":"30d","metadata":{"service":"ai-memory"}}' \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["key"])')
  sed -i.bak "s|^AI_MEMORY_LITELLM_KEY=.*|AI_MEMORY_LITELLM_KEY=${SVC_KEY}|" .env && rm -f .env.bak
  docker compose up -d ai-memory >/dev/null
  echo "service key written to local/.env and ai-memory restarted"
fi

echo "== LiteLLM developer key for ${USERNAME}"
DEV_LLM_KEY=$(curl -fsS "${AUTH[@]}" "$LITELLM/key/generate" \
  -d "{\"key_alias\":\"dev-${USERNAME}\",\"user_id\":\"${USERNAME}\",\"team_id\":\"${TEAM_ID}\",\"metadata\":{\"email\":\"${EMAIL}\"}}" \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["key"])')

echo "== ai-memory user + API key for ${USERNAME}"
docker compose exec -T ai-memory ai-memory user add-human \
  --username "${USERNAME}" --email "${EMAIL}" --name "${USERNAME}"
DEV_MEM_KEY=$(docker compose exec -T ai-memory ai-memory api-key add \
  --username "${USERNAME}" --label "poc-laptop" --json \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("secret") or d.get("token") or d)')

cat <<OUT

Developer credentials for ${USERNAME} (shown once):
  ANTHROPIC_AUTH_TOKEN=${DEV_LLM_KEY}      # Claude Code -> LiteLLM
  AI_MEMORY_AUTH_TOKEN=${DEV_MEM_KEY}      # hooks + MCP -> ai-memory

Next: clients/setup-developer.sh
OUT
