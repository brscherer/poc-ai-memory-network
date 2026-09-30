#!/usr/bin/env bash
# What the project memory holds right now, as one user sees it: the
# briefing a new session gets, then each decision page with its author.
#
#   demo/decisions.sh           # as alice
#   demo/decisions.sh carol     # as someone else
. "$(dirname "$0")/lib.sh"
AS="${1:-alice}"
ensure_laptop_lb
scope="{\"workspace\":\"$DEMO_WS\",\"project\":\"$DEMO_PROJECT\"}"

log "Briefing for $DEMO_WS/$DEMO_PROJECT (as $AS)"
brief="$(mcp "$AS" memory_briefing "$(jq -c '. + {settled_first: true}' <<<"$scope")")"
jq -r '"sessions: \(.counts.sessions)   observations: \(.counts.observations)   pages: \(.counts.pages_latest)"' <<<"$brief"

log "Decision pages"
# Pinned decisions and rules come back as "settled"; add any unpinned ones.
paths="$(jq -r '[.settled[]?.path, (.recent_pages[]? | select(.kind == "decision") | .path)] | unique[]' <<<"$brief")"
[ -n "$paths" ] || { echo "(none yet)"; exit 0; }
for p in $paths; do
  mcp "$AS" memory_read_page "$(jq -c --arg p "$p" '. + {path: $p}' <<<"$scope")" | jq -r '
    "\n\(.path)  —  written by \(.frontmatter.last_modified_by.username // "?")",
    (.body | split("\n") | map(select(length > 0)) | .[0:8] | map("  " + .) | join("\n"))'
done
