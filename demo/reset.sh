#!/usr/bin/env bash
# Start the story over: forget everything about poc/tiny-shop on the server
# and give every user a fresh checkout. Identities and Claude logins stay.
. "$(dirname "$0")/lib.sh"

log "Purge $DEMO_WS/$DEMO_PROJECT from ai-memory"
mem_exec purge-project --workspace "$DEMO_WS" --project "$DEMO_PROJECT" --confirm || true

log "Fresh checkouts"
for d in "$DEMO_HOME"/*/tiny-shop; do [ -d "$d" ] && rm -rf "$d" && echo "removed $d"; done
C="$(guest)"
[ -n "$C" ] && docker exec "$C" sh -c 'rm -rf /home/*/tiny-shop' && echo "removed EC2 checkouts"

"$DEMO_DIR/setup.sh"
