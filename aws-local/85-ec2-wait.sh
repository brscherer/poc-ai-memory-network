#!/usr/bin/env bash
# Wait for the guest Tofu launched to finish its user-data, and keep its log
# as evidence (90-verify.sh asserts against it).
. "$(dirname "$0")/lib.sh"
HOST_NAME="$(tofu_out host host_name)"
ID="$(tofu_out host instance_id)"

log "Waiting for $HOST_NAME ($ID) to finish bootstrapping"
C=$(docker ps --format '{{.Names}}' | grep -- "$ID" | head -1)
[ -n "$C" ] || { echo "no container for $ID"; exit 1; }
for _ in $(seq 1 180); do
  docker exec "$C" grep -qE '\[bootstrap\] (done|FAILED)' /var/log/ai-host-bootstrap.log 2>/dev/null && break
  sleep 5
done
docker exec "$C" cat /var/log/ai-host-bootstrap.log | tee "$STATE/ec2-$HOST_NAME.log" | grep -avE 'lock|debconf| INFO '
grep -q '\[bootstrap\] done' "$STATE/ec2-$HOST_NAME.log"
