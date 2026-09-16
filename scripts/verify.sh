#!/usr/bin/env bash
# End-to-end verification of the gateway + shared-memory path.
#
#   GATEWAY_KEY=<developer LiteLLM key> MEMORY_KEY=<developer aim_ key> scripts/verify.sh
#
# Checks, in order:
#   1. LiteLLM is alive
#   2. Claude (Bedrock) answers through LiteLLM's Anthropic-format endpoint
#   3. ai-memory is alive and rejects unauthenticated calls
#   4. ai-memory can reach Claude through LiteLLM (consolidation path)
#   5. A developer key can write + read a page in project A
#   6. A second project cannot see it (per-project scoping)
#   7. A search by the same user from project A finds it again (persistence)
set -uo pipefail
cd "$(dirname "$0")/../local"
set -a; . ./.env; set +a
: "${GATEWAY_KEY:?export GATEWAY_KEY}"; : "${MEMORY_KEY:?export MEMORY_KEY}"

LITELLM=http://127.0.0.1:4000
MEMORY=http://127.0.0.1:49375
WS=poc
PA=verify-project-a
PB=verify-project-b
CANARY="CANARY-$(date +%s)"
pass=0; fail=0
ok()  { echo "  PASS  $*"; pass=$((pass+1)); }
bad() { echo "  FAIL  $*"; fail=$((fail+1)); }
mem() { docker compose exec -T -e AI_MEMORY_AUTH_TOKEN="$MEMORY_KEY" ai-memory ai-memory "$@"; }

echo "1. LiteLLM liveness"
curl -fsS "$LITELLM/health/liveliness" >/dev/null && ok "litellm up" || bad "litellm down"

echo "2. Claude via LiteLLM (Anthropic format)"
out=$(curl -sS "$LITELLM/v1/messages" \
  -H "Authorization: Bearer $GATEWAY_KEY" -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d '{"model":"claude-haiku-4-5","max_tokens":20,"messages":[{"role":"user","content":"Reply with: pong"}]}')
echo "$out" | grep -qi pong && ok "bedrock answered" || bad "unexpected: ${out:0:200}"

echo "3. ai-memory auth"
code=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$MEMORY/mcp" -H 'content-type: application/json' -d '{}')
[ "$code" = 401 ] && ok "anonymous call rejected (401)" || bad "anonymous call got $code (expected 401)"

echo "4. ai-memory -> LiteLLM -> Bedrock"
docker compose exec -T ai-memory ai-memory llm-test --prompt "Reply with: pong" 2>&1 | grep -qi pong \
  && ok "consolidation LLM reachable" || bad "llm-test failed (check AI_MEMORY_LITELLM_KEY)"

echo "5. write + read in $WS/$PA"
mem write-page --workspace "$WS" --project "$PA" --path notes/verify.md \
  --body "$(printf '# Verify\n\nToken: %s\n' "$CANARY")" --tag verify >/dev/null \
  && ok "page written" || bad "write failed"
mem search "$CANARY" --workspace "$WS" --project "$PA" | grep -q notes/verify.md \
  && ok "page found in project A" || bad "page not found in project A"

echo "6. isolation: $WS/$PB"
mem write-page --workspace "$WS" --project "$PB" --path notes/empty.md --body "# Empty" >/dev/null
mem search "$CANARY" --workspace "$WS" --project "$PB" | grep -q notes/verify.md \
  && bad "LEAK: project B sees project A page" || ok "project B cannot see it"

echo "7. persistence across restart"
docker compose restart ai-memory >/dev/null; sleep 5
mem search "$CANARY" --workspace "$WS" --project "$PA" | grep -q notes/verify.md \
  && ok "page survived restart" || bad "page lost after restart"

echo
echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
