# Shared settings for the demo scripts. Source, don't execute.
. "$(dirname "${BASH_SOURCE[0]}")/../aws-local/lib.sh"
DEMO_DIR="$REPO_DIR/demo"
# Each "laptop" user gets an isolated home here: their own Claude Code
# profile, ai-memory hook state and checkout. Nothing touches ~/.claude.
DEMO_HOME="${DEMO_HOME:-$HOME/ai-memory-demo}"
export RUST_LOG="${RUST_LOG:-warn}"   # keep ai-memory CLI output to warnings
DEMO_WS=poc
DEMO_PROJECT="${DEMO_PROJECT:-tiny-shop}"
AI_MEMORY_VERSION="${AI_MEMORY_VERSION:-2.2.1}"

# Laptops reach ai-memory the way they would reach the internal ALB: a relay
# on the Docker network forwards 127.0.0.1:14375 to the NodePort, so their
# traffic crosses the same Service and NetworkPolicy as the EC2 host's.
LAPTOP_LB=aimem-laptop-lb
LAPTOP_LB_IMAGE=alpine/socat@sha256:5ffbd6ae916cbad86a58fabe0d6d5a6fd5c2b47ddf031e82996baac9300e732f
LAPTOP_MEMORY_PORT=14375
LAPTOP_MEMORY_URL="http://127.0.0.1:$LAPTOP_MEMORY_PORT"
GUEST_MEMORY_URL="http://floci-eks-ai-platform:30374"
# Native ai-memory for the laptop profiles. Hooks and the MCP bridge must run
# on this machine: a containerised `ai-memory` (such as the upstream Docker
# wrapper) resolves 127.0.0.1 to its own container and cannot reach the relay.
LAPTOP_BIN="$DEMO_HOME/.ai-memory-$AI_MEMORY_VERSION/ai-memory"

# guest : name of the container behind the EC2 instance from tofu/host
guest() {
  local id; id="$(tofu_out host instance_id)"
  docker ps --format '{{.Names}}' | grep -- "$id" | head -1
}
# memory_key USER : that user's aim_ key from Secrets Manager
memory_key() { secret_value "ai-memory/developers/$1/api-key"; }
# ensure_laptop_lb : start the relay unless it is already running
ensure_laptop_lb() {
  [ "$(docker inspect -f '{{.State.Running}}' "$LAPTOP_LB" 2>/dev/null)" = true ] && return 0
  docker rm -f "$LAPTOP_LB" >/dev/null 2>&1 || true
  docker run -d --name "$LAPTOP_LB" --restart unless-stopped --network "$NETWORK" \
    -p "127.0.0.1:$LAPTOP_MEMORY_PORT:$LAPTOP_MEMORY_PORT" "$LAPTOP_LB_IMAGE" \
    "tcp-listen:$LAPTOP_MEMORY_PORT,fork,reuseaddr" "tcp-connect:${GUEST_MEMORY_URL#http://}" >/dev/null
  wait_http "$LAPTOP_MEMORY_URL/mcp"
}
# mcp USER TOOL JSON_ARGS : call one MCP tool as USER
mcp() {
  AI_MEMORY_SERVER_URL="$LAPTOP_MEMORY_URL" AI_MEMORY_AUTH_TOKEN="$(memory_key "$1")" \
    "$REPO_DIR/scripts/mcp-call.sh" "$2" "$3"
}
