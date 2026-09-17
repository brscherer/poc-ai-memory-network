#!/usr/bin/env bash
# Credential provisioning, the same flow as scripts/bootstrap-keys.sh but
# against the in-cluster services, with every secret landing in Secrets Manager.
#   - service key for ai-memory -> LiteLLM (then ESO syncs it into the pod)
#   - a developer (laptop) identity:  LiteLLM key + ai-memory user/key
#   - an EC2 host identity:           LiteLLM key + ai-memory user/key
. "$(dirname "$0")/lib.sh"
DEV_USER="${DEV_USER:-jdoe}"
HOST_NAME="${HOST_NAME:-ec2-dev-1}"

port_forward ai-gateway litellm 14000 4000
MASTER=$(secret_value ai-gateway/litellm/master-key)
llm() { curl -fsS -H "Authorization: Bearer $MASTER" -H 'Content-Type: application/json' "http://127.0.0.1:14000$1" -d "$2"; }

# issue_llm_key SECRET_NAME JSON_BODY
issue_llm_key() {
  if has_secret "$1" && [ "$(secret_value "$1")" != pending-bootstrap ]; then echo "exists: $1"; return; fi
  put_secret "$1" "$(llm /key/generate "$2" | jq -r .key)"; echo "issued: $1"
}
# issue_mem_key USERNAME SECRET_NAME
issue_mem_key() {
  if has_secret "$2"; then echo "exists: $2"; return; fi
  mem_exec user add-human --username "$1" --email "$1@example.com" --name "$1" >/dev/null 2>&1  # API-key only; temp password unused
  put_secret "$2" "$(mem_exec api-key add --username "$1" --label aws-local --json | jq -r '.secret // .token // .api_key // .key')"
  echo "issued: $2"
}

log "LiteLLM team + service key for ai-memory"
# Key tags are a LiteLLM Enterprise feature; the dedicated key alias does the attribution.
TEAM_ID=$(curl -fsS -H "Authorization: Bearer $MASTER" http://127.0.0.1:14000/team/list | jq -r '.[] | select(.team_alias=="team-a") | .team_id' | head -1)
[ -n "$TEAM_ID" ] || TEAM_ID=$(llm /team/new '{"team_alias":"team-a","models":["claude-opus-5","claude-sonnet-5","claude-haiku-4-5"]}' | jq -r .team_id)
echo "team-a: $TEAM_ID"
BEFORE=$(secret_value ai-memory/team-a/litellm-key)
issue_llm_key ai-memory/team-a/litellm-key \
  '{"key_alias":"svc-ai-memory-team-a","models":["memory-consolidation"],"max_budget":50,"budget_duration":"30d","metadata":{"service":"ai-memory","tenant":"team-a"}}'
if [ "$BEFORE" != "$(secret_value ai-memory/team-a/litellm-key)" ]; then
  log "Sync the new service key into the pod (ESO) and restart"
  kubectl -n ai-memory-team-a annotate externalsecret ai-memory force-sync="$(date +%s)" --overwrite >/dev/null
  sleep 5
  kubectl -n ai-memory-team-a rollout restart statefulset/ai-memory
  kubectl -n ai-memory-team-a rollout status statefulset/ai-memory --timeout=5m
fi

log "Developer identity: $DEV_USER"
issue_llm_key "ai-gateway/developers/$DEV_USER/litellm" \
  "{\"key_alias\":\"dev-$DEV_USER\",\"user_id\":\"$DEV_USER\",\"team_id\":\"$TEAM_ID\"}"
issue_mem_key "$DEV_USER" "ai-memory/developers/$DEV_USER/api-key"

log "EC2 host identity: $HOST_NAME"
issue_llm_key "ai-gateway/hosts/$HOST_NAME/litellm" \
  "{\"key_alias\":\"host-$HOST_NAME\",\"user_id\":\"host-$HOST_NAME\",\"team_id\":\"$TEAM_ID\"}"
issue_mem_key "host-$HOST_NAME" "ai-memory/hosts/$HOST_NAME/api-key"

log "Identities known to ai-memory"
mem_exec user list
