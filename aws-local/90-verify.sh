#!/usr/bin/env bash
# End-to-end evidence run. Every check prints PASS/FAIL and the report is
# written to aws-local/evidence/report-<timestamp>.md (no secret values).
. "$(dirname "$0")/lib.sh"
set +e
set +m   # no "Terminated" job-control noise when port-forwards are killed
DEV_USER="${DEV_USER:-jdoe}"; HOST_NAME="${HOST_NAME:-ec2-dev-1}"
. "$STATE/image.env"
mkdir -p "$AWS_LOCAL_DIR/evidence"
TS=$(date -u +%Y%m%dT%H%M%SZ)
REPORT="$AWS_LOCAL_DIR/evidence/report-$TS.md"
PASS=0; FAIL=0; ROWS=""
check() { # check "Area" "Claim" <command...>
  local area="$1" claim="$2"; shift 2
  local out; out=$("$@" 2>&1); local rc=$?
  local detail; detail=$(printf '%s' "$out" | tr '\n' ' ' | sed 's/|/\\|/g' | cut -c1-140)
  if [ $rc -eq 0 ]; then PASS=$((PASS+1)); s="PASS"; else FAIL=$((FAIL+1)); s="**FAIL**"; fi
  printf '%-6s %-10s %s\n' "$s" "$area" "$claim"
  ROWS="$ROWS| $s | $area | $claim | \`$detail\` |"$'\n'
}
expect_code() { # expect_code CODE curl-args...
  local want=$1; shift; local got; got=$(curl -s -o /dev/null -w '%{http_code}' -m 10 "$@"); echo "HTTP $got"; [ "$got" = "$want" ]
}

port_forward ai-gateway litellm 14000 4000
port_forward ai-memory-team-a ai-memory 14374 49374
DEV_LLM=$(secret_value "ai-gateway/developers/$DEV_USER/litellm")
DEV_MEM=$(secret_value "ai-memory/developers/$DEV_USER/api-key")
MSG='{"model":"claude-haiku-4-5","max_tokens":32,"messages":[{"role":"user","content":"ping"}]}'
# Developer operations go through MCP, like an agent (CLI page commands are root-only).
export AI_MEMORY_SERVER_URL=http://127.0.0.1:14374 AI_MEMORY_AUTH_TOKEN="$DEV_MEM"
MCP="$REPO_DIR/scripts/mcp-call.sh"
q() { "$MCP" memory_query "$(jq -nc --arg p "$1" --arg q "$2" '{workspace:"poc",project:$p,query:$q}')" | jq -r '.hits[].path'; }
w() { "$MCP" memory_write_page "$(jq -nc --arg p "$1" --arg path "$2" --arg b "$3" '{workspace:"poc",project:$p,path:$path,body:$b}')" >/dev/null; }
CANARY="CANARY-$TS"

echo "== AWS layer (floci)"
check AWS "floci is healthy" sh -c 'curl -sf http://127.0.0.1:4566/_floci/health | jq -r .version'
check AWS "EKS cluster ACTIVE" aws eks describe-cluster --name "$CLUSTER" --query cluster.status --output text
check AWS "kubectl authenticates via aws eks get-token" kubectl auth whoami -o jsonpath='{.status.userInfo.username}'
check AWS "ai-memory image mirrored in ECR (immutable tag)" aws ecr describe-images --repository-name mirror/ai-memory \
  --image-ids imageTag="$AI_MEMORY_TAG" --query 'imageDetails[0].imageDigest' --output text
check AWS "pod runs the ECR-mirrored image" sh -c "kubectl -n ai-memory-team-a get pod ai-memory-0 -o jsonpath='{.spec.containers[0].image}' | grep -F '$AI_MEMORY_MIRROR:$AI_MEMORY_TAG'"
check AWS "ESO store reads Secrets Manager" kubectl get clustersecretstore aws-secrets-manager -o jsonpath='{.status.conditions[0].reason}'
check AWS "gateway secrets synced by ESO" kubectl -n ai-gateway wait --for=condition=Ready externalsecret/litellm --timeout=5s
check AWS "memory secrets synced by ESO" kubectl -n ai-memory-team-a wait --for=condition=Ready externalsecret/ai-memory --timeout=5s

echo "== Inference plane"
check Gateway "developer key -> LiteLLM -> Bedrock (Anthropic format)" sh -c \
  "curl -fsS http://127.0.0.1:14000/v1/messages -H 'Authorization: Bearer $DEV_LLM' -H 'anthropic-version: 2023-06-01' -H 'content-type: application/json' -d '$MSG' | jq -er '.content[0].text'"
check Gateway "reply was produced by Bedrock Runtime (floci), not LiteLLM" sh -c \
  "curl -fsS http://127.0.0.1:14000/v1/messages -H 'Authorization: Bearer $DEV_LLM' -H 'anthropic-version: 2023-06-01' -H 'content-type: application/json' -d '$MSG' | jq -er '.content[0].text' | grep -i 'floci stub'"
check Gateway "unknown key rejected" expect_code 401 http://127.0.0.1:14000/v1/messages \
  -H 'Authorization: Bearer sk-not-a-key' -H 'content-type: application/json' -d "$MSG"
check Gateway "developer key cannot use the memory service model" sh -c \
  "! curl -fsS http://127.0.0.1:14000/v1/messages -H 'Authorization: Bearer $DEV_LLM' -H 'anthropic-version: 2023-06-01' -H 'content-type: application/json' -d '{\"model\":\"memory-consolidation\",\"max_tokens\":8,\"messages\":[{\"role\":\"user\",\"content\":\"x\"}]}' >/dev/null"

echo "== Memory plane"
check Memory "anonymous MCP call rejected" expect_code 401 -X POST http://127.0.0.1:14374/mcp -H 'content-type: application/json' -d '{}'
check Memory "ai-memory -> LiteLLM -> Bedrock (consolidation path)" sh -c \
  "kubectl -n ai-memory-team-a exec ai-memory-0 -c ai-memory -- sh -c 'ai-memory llm-test --provider openai-compat --model \$AI_MEMORY_LLM_MODEL --prompt pong' 2>&1 | grep -A1 usage:"
check Memory "developer writes a page via MCP (poc/verify-a)" w verify-a notes/verify.md "# Verify
Token: $CANARY"
check Memory "developer finds it in poc/verify-a" sh -c "$(declare -f q); MCP='$MCP'; q verify-a '$CANARY' | grep -x notes/verify.md"
check Memory "poc/verify-b cannot see it (isolation)" sh -c "$(declare -f q w); MCP='$MCP'; w verify-b notes/empty.md '# Empty'; ! q verify-b '$CANARY' | grep -x notes/verify.md"
check Memory "developer reads the note written by the EC2 host" sh -c "$(declare -f q); MCP='$MCP'; q shared-demo 'EC2-EVIDENCE-$HOST_NAME' | grep -x 'notes/from-$HOST_NAME.md'"
check Memory "EC2 note is attributed to the host identity" sh -c "\"$MCP\" memory_read_page '{\"workspace\":\"poc\",\"project\":\"shared-demo\",\"path\":\"notes/from-$HOST_NAME.md\"}' | jq -er '.frontmatter.last_modified_by.username' | grep -x 'host-$HOST_NAME'"
check Memory "developer note is attributed to the developer" sh -c "\"$MCP\" memory_read_page '{\"workspace\":\"poc\",\"project\":\"verify-a\",\"path\":\"notes/verify.md\"}' | jq -er '.frontmatter.last_modified_by.username' | grep -x '$DEV_USER'"
check Memory "developer key cannot call admin routes" sh -c "! kubectl -n ai-memory-team-a exec ai-memory-0 -c ai-memory -- env AI_MEMORY_AUTH_TOKEN='$DEV_MEM' ai-memory search x --workspace poc --project verify-a 2>&1 | grep -q verify.md"
kubectl -n ai-memory-team-a delete pod ai-memory-0 --wait=true >/dev/null
kubectl -n ai-memory-team-a wait --for=condition=Ready pod/ai-memory-0 --timeout=180s >/dev/null
kill $PF_PIDS 2>/dev/null; PF_PIDS=""
port_forward ai-memory-team-a ai-memory 14374 49374
wait_http http://127.0.0.1:14374/mcp   # the tunnel listens before it can reach the new pod
check Memory "page survives pod replacement (PVC)" sh -c "$(declare -f q); MCP='$MCP'; q verify-a '$CANARY' | grep -x notes/verify.md"
check Memory "snapshot shipped to S3" sh -c "for i in \$(seq 1 20); do aws s3 ls s3://$BACKUP_BUCKET/team-a/ | grep -q tar.gz && aws s3 ls s3://$BACKUP_BUCKET/team-a/ | tail -1 && exit 0; sleep 6; done; exit 1"

echo "== Network policy"
# k3s programs NetworkPolicy from pod-IP sets that it re-syncs periodically,
# so a pod created seconds ago is not in them yet. Use long-lived probe pods
# and retry each assertion until the sync catches up.
MEM_URL=http://ai-memory.ai-memory-team-a.svc.cluster.local:49374/mcp
LLM_URL=http://litellm.ai-gateway.svc.cluster.local:4000/health/liveliness
# np-outsider and np-agents (labelled ai-platform/memory-client) come from
# tofu/cluster.
mkprobe() { # mkprobe NAMESPACE NAME LABELS
  kubectl -n "$1" get pod "$2" >/dev/null 2>&1 && return 0
  kubectl -n "$1" run "$2" --image=curlimages/curl:8.10.1 --labels="$3" --restart=Never \
    --overrides='{"spec":{"securityContext":{"runAsNonRoot":true,"runAsUser":100,"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"c","image":"curlimages/curl:8.10.1","command":["sleep","3600"],"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}}]}}' \
    --command -- sleep 3600 >/dev/null
}
mkprobe np-outsider probe app=probe
mkprobe np-agents probe app=probe
mkprobe ai-memory-team-a probe app.kubernetes.io/name=ai-memory
for ns in np-outsider np-agents ai-memory-team-a; do kubectl -n $ns wait --for=condition=Ready pod/probe --timeout=120s >/dev/null; done
code() { kubectl -n "$1" exec probe -- curl -s -o /dev/null -w '%{http_code}' -m 6 "$2" 2>/dev/null; }
# want_code NS URL EXPECTED : retry while the policy sync settles
want_code() {
  local got
  for _ in $(seq 1 30); do got=$(code "$1" "$2"); [ "$got" = "$3" ] && { echo "HTTP $got"; return 0; }; sleep 10
  done
  echo "HTTP $got (expected $3)"; return 1
}
check NetPol "unlabelled namespace cannot reach ai-memory" want_code np-outsider "$MEM_URL" 000
check NetPol "agent namespace (memory-client) can reach ai-memory" want_code np-agents "$MEM_URL" 401
check NetPol "ai-memory pods cannot reach the internet" want_code ai-memory-team-a https://example.com 000
check NetPol "ai-memory pods can reach LiteLLM" want_code ai-memory-team-a "$LLM_URL" 200

echo "== EC2 host"
LOG="$STATE/ec2-$HOST_NAME.log"
check EC2 "IMDS exposes the ai-host instance profile" grep -m1 'IMDS role: ai-host' "$LOG"
check EC2 "guest AWS CLI uses the instance-role credential chain" grep -m1 'credential source: iam-role' "$LOG"
check EC2 "guest read its keys from Secrets Manager and installed hooks" grep -m1 'hooks installed' "$LOG"
check EC2 "guest called the gateway with its host key" grep -m1 '"stop_reason"' "$LOG"
check EC2 "guest wrote to shared memory and found its note" grep -m1 "found.*from-$HOST_NAME" "$LOG"

{
  echo "# aws-local evidence report"
  echo
  echo "- Run: $TS"
  echo "- floci: $(curl -s http://127.0.0.1:4566/_floci/health | jq -r .version), Bedrock backend: $(docker exec aimem-floci printenv FLOCI_SERVICES_BEDROCK_RUNTIME_BACKEND)"
  echo "- EKS: $(kubectl version -o json | jq -r .serverVersion.gitVersion), ai-memory $AI_MEMORY_TAG, image $AI_MEMORY_DIGEST"
  echo "- Result: **$PASS passed, $FAIL failed**"
  echo
  echo "| Result | Area | Claim | Detail |"
  echo "|---|---|---|---|"
  printf '%s' "$ROWS"
} > "$REPORT"
echo; echo "passed=$PASS failed=$FAIL  report: ${REPORT#$REPO_DIR/}"
[ "$FAIL" -eq 0 ]
