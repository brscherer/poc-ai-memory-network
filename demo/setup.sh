#!/usr/bin/env bash
# Prepare the shared-memory demo on top of a running aws-local stack.
#
#   demo/setup.sh            alice (laptop), bob (EC2 host), carol (laptop)
#   demo/setup.sh carol      just one of them; safe to re-run
#
# Every user gets their own ai-memory identity (aim_ key in Secrets Manager)
# and their own checkout of demo/seed/tiny-shop. Inference uses each user's
# own Claude login instead of the emulated gateway (Bedrock is a stub in
# aws-local), so the memory plane is the only shared thing here.
. "$(dirname "$0")/lib.sh"
LAPTOP_USERS="alice carol"
EC2_USERS="bob"
USERS="${*:-$LAPTOP_USERS $EC2_USERS}"

# issue_memory_key USER : ai-memory user + aim_ key, stored in Secrets Manager
issue_memory_key() {
  local name="ai-memory/developers/$1/api-key"
  if has_secret "$name"; then echo "exists: $name"; return; fi
  mem_exec user add-human --username "$1" --email "$1@example.com" --name "$1" >/dev/null 2>&1 || true
  put_secret "$name" "$(mem_exec api-key add --username "$1" --label demo --json | jq -r '.secret // .token // .api_key // .key')"
  echo "issued: $name"
}

# checkout DIR : a fresh git repository with the seed project, unless present
checkout() {
  [ -d "$1/.git" ] && return 0
  mkdir -p "$1" && cp -R "$DEMO_DIR/seed/tiny-shop/." "$1/"
  git -C "$1" init -q -b main
  git -C "$1" add -A
  git -C "$1" -c user.name=demo -c user.email=demo@example.com commit -qm "tiny-shop seed"
}

# ensure_laptop_bin : checksum-verified native ai-memory release for this OS
ensure_laptop_bin() {
  [ -x "$LAPTOP_BIN" ] && return 0
  local os arch f url
  case "$(uname -s)" in Darwin) os=macos ;; Linux) os=linux ;; *) echo "unsupported OS" >&2; return 1 ;; esac
  case "$(uname -m)" in arm64 | aarch64) arch=aarch64 ;; x86_64 | amd64) arch=x86_64 ;; esac
  f="ai-memory-$os-$arch.tar.gz"
  url="https://github.com/akitaonrails/ai-memory/releases/download/v$AI_MEMORY_VERSION/$f"
  mkdir -p "$STATE/cache" "$(dirname "$LAPTOP_BIN")"
  [ -f "$STATE/cache/$f" ] || curl -fsSL -o "$STATE/cache/$f" "$url"
  [ "$(shasum -a 256 "$STATE/cache/$f" | awk '{print $1}')" = "$(curl -fsSL "$url.sha256" | awk '{print $1}')" ] \
    || { echo "checksum mismatch for $f" >&2; return 1; }
  tar -xzf "$STATE/cache/$f" -C "$(dirname "$LAPTOP_BIN")"
  echo "installed $("$LAPTOP_BIN" --version) -> $LAPTOP_BIN"
}

# setup_laptop USER : an isolated Claude Code profile on this machine
setup_laptop() {
  local home="$DEMO_HOME/$1" key; key="$(memory_key "$1")"
  ensure_laptop_bin
  ensure_laptop_lb
  mkdir -p "$home/claude" "$home/ai-memory"
  checkout "$home/tiny-shop"
  # Hooks: capture what happens in the session, inject the briefing at start.
  # The token and the staged scripts go to the user's own data dir.
  "$LAPTOP_BIN" install-hooks --agent claude-code --apply \
    --config-file "$home/claude/settings.json" \
    --hooks-dir "$(dirname "$LAPTOP_BIN")/hooks" \
    --data-dir "$home/ai-memory" \
    --server-url "$LAPTOP_MEMORY_URL" --auth-token "$key" \
    --capture-mode allowlist >/dev/null
  # MCP: the memory_* tools, with the session id forwarded so the agent can
  # omit workspace/project. The bridge must be this native binary, not
  # whatever `ai-memory` is first on PATH.
  "$LAPTOP_BIN" install-mcp --client claude-code --session-aware --apply \
    --config-file "$home/claude/.claude.json" \
    --server-url "$LAPTOP_MEMORY_URL" --auth-token "$key" >/dev/null
  jq --arg bin "$LAPTOP_BIN" '.mcpServers["ai-memory"].command = $bin' "$home/claude/.claude.json" > "$home/claude/.claude.json.tmp" \
    && mv "$home/claude/.claude.json.tmp" "$home/claude/.claude.json"
  chmod 600 "$home/claude/settings.json" "$home/claude/.claude.json"
  echo "laptop profile ready: $home"
}

# setup_ec2 USER : a Linux account on the EC2 host with Claude Code + memory
setup_ec2() {
  local c; c="$(guest)"
  [ -n "$c" ] || { echo "EC2 guest not running; run aws-local/up.sh" >&2; return 1; }
  docker exec -i -e U="$1" -e KEY="$(memory_key "$1")" -e URL="$GUEST_MEMORY_URL" "$c" bash -s <<'GUEST'
set -euo pipefail
command -v git >/dev/null || { apt-get update -qq && apt-get install -y -qq git >/dev/null; }
id "$U" >/dev/null 2>&1 || useradd -m -s /bin/bash "$U"
# Demo inference mode: the user's own Claude login instead of the (stubbed)
# gateway. Memory settings stay managed. The gateway version is kept aside.
M=/etc/claude-code/managed-settings.json
[ -f "$M.gateway" ] || cp "$M" "$M.gateway"
jq '{env: {AI_MEMORY_SERVER_URL: .env.AI_MEMORY_SERVER_URL}}' "$M.gateway" > "$M"
su - "$U" -c 'test -x ~/.local/bin/claude || curl -fsSL https://claude.ai/install.sh | bash >/dev/null'
su - "$U" -c 'grep -q local/bin ~/.bashrc || echo "export PATH=\$HOME/.local/bin:\$PATH" >> ~/.bashrc'
su - "$U" -c "ai-memory install-hooks --agent claude-code --apply --server-url '$URL' --auth-token '$KEY' --capture-mode allowlist >/dev/null"
su - "$U" -c "ai-memory install-mcp --client claude-code --session-aware --apply --server-url '$URL' --auth-token '$KEY' >/dev/null"
GUEST
  docker exec -u "$1" "$c" test -d "/home/$1/tiny-shop/.git" || {
    docker cp "$DEMO_DIR/seed/tiny-shop" "$c:/home/$1/tiny-shop"
    docker exec "$c" chown -R "$1:$1" "/home/$1/tiny-shop"
    docker exec -u "$1" -w "/home/$1/tiny-shop" "$c" sh -c \
      'git init -q -b main && git add -A && git -c user.name=demo -c user.email=demo@example.com commit -qm "tiny-shop seed"'
  }
  echo "EC2 account ready: $1@$c"
}

for u in $USERS; do
  log "$u"
  issue_memory_key "$u"
  case " $EC2_USERS " in *" $u "*) setup_ec2 "$u" ;; *) setup_laptop "$u" ;; esac
done

log "Next"
echo "demo/laptop.sh alice    # first session (logs in to Claude on first run)"
echo "demo/ec2.sh bob         # second session, on the EC2 host"
echo "demo/decisions.sh       # what the project memory holds"
