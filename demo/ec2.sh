#!/usr/bin/env bash
# Open a Claude Code session as a user on the EC2 host (the floci guest).
#
#   demo/ec2.sh bob           # Claude Code in bob's checkout
#   demo/ec2.sh bob bash      # a shell instead, to look around
#
# The first run asks for a Claude login: open the printed URL in your
# browser and paste the code back.
. "$(dirname "$0")/lib.sh"
U="${1:-bob}"
C="$(guest)"
[ -n "$C" ] || { echo "EC2 guest not running; run aws-local/up.sh" >&2; exit 1; }
exec docker exec -it -u "$U" -w "/home/$U/tiny-shop" -e TERM="${TERM:-xterm-256color}" \
  "$C" bash -lc "${2:-~/.local/bin/claude}"
