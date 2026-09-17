#!/usr/bin/env bash
# EC2: launch a developer/agent host with the ai-host instance profile and
# the local user-data. Its output is the evidence that an EC2 guest can reach
# Secrets Manager (via IMDS creds), the gateway and shared memory.
. "$(dirname "$0")/lib.sh"
HOST_NAME="${HOST_NAME:-ec2-dev-1}"
# Native-arch AMI: an emulated guest is slow enough that floci's IMDS proxy
# setup times out, and the guest then silently falls back to static keys.
case "$(uname -m)" in
  arm64|aarch64) DEFAULT_AMI=ami-ubuntu2404-arm64; DEFAULT_TYPE=t4g.medium ;;
  *)             DEFAULT_AMI=ami-ubuntu2404-amd64; DEFAULT_TYPE=t3.medium ;;
esac
EC2_AMI="${EC2_AMI:-$DEFAULT_AMI}"
EC2_TYPE="${EC2_TYPE:-$DEFAULT_TYPE}"
. "$STATE/image.env"

EXISTING=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=$HOST_NAME" "Name=instance-state-name,Values=pending,running" \
  --query 'Reservations[].Instances[].InstanceId' --output text)
if [ -n "$EXISTING" ]; then
  log "Replacing $HOST_NAME ($EXISTING)"
  aws ec2 terminate-instances --instance-ids $EXISTING >/dev/null; sleep 5
fi

sed -e "s/__HOST_NAME__/$HOST_NAME/" -e "s/__AI_MEMORY_VERSION__/$AI_MEMORY_TAG/" -e "s/__ARTIFACTS_BUCKET__/$ARTIFACTS_BUCKET/" \
  "$AWS_LOCAL_DIR/ec2/user-data.sh.tmpl" > "$STATE/user-data-$HOST_NAME.sh"

log "RunInstances $HOST_NAME"
ID=$(aws ec2 run-instances --image-id "$EC2_AMI" --instance-type "$EC2_TYPE" \
  --iam-instance-profile Name=ai-host \
  --user-data "file://$STATE/user-data-$HOST_NAME.sh" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$HOST_NAME}]" \
  --query 'Instances[0].InstanceId' --output text)
aws ec2 wait instance-running --instance-ids "$ID"
echo "$ID running"
echo "$ID" > "$STATE/instance-$HOST_NAME"

log "Waiting for user-data to finish"
C=$(docker ps --format '{{.Names}}' | grep -- "$ID" | head -1 || true)
[ -n "$C" ] || C=$(docker ps -q --filter "label=floci.ec2.instance-id=$ID" | head -1)
echo "container: $C"
for _ in $(seq 1 180); do
  docker exec "$C" grep -qE '\[bootstrap\] (done|FAILED)' /var/log/ai-host-bootstrap.log 2>/dev/null && break
  sleep 5
done
docker exec "$C" cat /var/log/ai-host-bootstrap.log | tee "$STATE/ec2-$HOST_NAME.log"
grep -q '\[bootstrap\] done' "$STATE/ec2-$HOST_NAME.log"
