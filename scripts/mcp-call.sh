#!/usr/bin/env bash
# Call one ai-memory MCP tool over HTTP and print the tool's text result.
#
#   AI_MEMORY_SERVER_URL=http://127.0.0.1:49374 AI_MEMORY_AUTH_TOKEN=aim_... \
#     scripts/mcp-call.sh memory_query '{"workspace":"poc","project":"x","query":"foo"}'
#
# In multi-user mode the CLI page commands (write-page, search, read-page) use
# root-only /admin routes, so regular users go through MCP, exactly like an
# agent does. Exits non-zero on transport errors and on isError results.
set -euo pipefail
tool="${1:?tool name}"; args="${2:-{\}}"
: "${AI_MEMORY_SERVER_URL:?}" "${AI_MEMORY_AUTH_TOKEN:?}"
body=$(jq -nc --arg t "$tool" --argjson a "$args" \
  '{jsonrpc:"2.0",id:1,method:"tools/call",params:{name:$t,arguments:$a}}')
resp=$(curl -fsS "${AI_MEMORY_SERVER_URL%/}/mcp" \
  -H "Authorization: Bearer $AI_MEMORY_AUTH_TOKEN" \
  -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
  -d "$body")
# Streamable HTTP may answer as SSE; keep only the JSON payload.
json=$(printf '%s\n' "$resp" | sed -n 's/^data: //p'); [ -n "$json" ] || json="$resp"
printf '%s' "$json" | jq -r '(.result.content // [])[] | .text // empty'
printf '%s' "$json" | jq -e '(.error == null) and (.result.isError != true)' >/dev/null
