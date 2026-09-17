#!/usr/bin/env bash
# Download (and checksum) the ai-memory release tarballs that Tofu then
# publishes to the artifact bucket. Kept out of Tofu because fetching and
# verifying upstream binaries is not infrastructure state.
. "$(dirname "$0")/lib.sh"
VER="${AI_MEMORY_VERSION:-2.2.1}"
mkdir -p "$STATE/cache"

log "ai-memory $VER release tarballs"
for arch in aarch64 x86_64; do
  f="ai-memory-linux-$arch.tar.gz"
  if [ ! -f "$STATE/cache/$f" ]; then
    curl -fsSL -o "$STATE/cache/$f" "https://github.com/akitaonrails/ai-memory/releases/download/v$VER/$f"
  fi
  curl -fsSL "https://github.com/akitaonrails/ai-memory/releases/download/v$VER/$f.sha256" | awk '{print $1}' > "$STATE/cache/$f.sha256"
  have=$(shasum -a 256 "$STATE/cache/$f" | awk '{print $1}')
  want=$(cat "$STATE/cache/$f.sha256")
  [ "$have" = "$want" ] || { echo "checksum mismatch for $f"; exit 1; }
  echo "  ok $f ${have:0:12}…"
done
