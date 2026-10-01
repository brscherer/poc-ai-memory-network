#!/usr/bin/env bash
# Open a Claude Code session as a "laptop" user (this machine, isolated profile).
#
#   demo/laptop.sh alice
#
# The first run asks for a Claude login and a theme: that profile is
# separate from your own ~/.claude.
. "$(dirname "$0")/lib.sh"
U="${1:?user, e.g. alice}"
[ -d "$DEMO_HOME/$U/claude" ] || { echo "no profile for $U; run demo/setup.sh $U" >&2; exit 1; }
ensure_laptop_lb
cd "$DEMO_HOME/$U/tiny-shop"
CLAUDE_CONFIG_DIR="$DEMO_HOME/$U/claude" exec claude "${@:2}"
