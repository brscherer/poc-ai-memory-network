#!/usr/bin/env bash
# Tear everything down, newest stack first, then floci and its data.
set -uo pipefail
cd "$(dirname "$0")"
TF_ARGS=${TF_ARGS:--auto-approve}
for stack in host cluster aws; do
  [ -f "tofu/$stack/terraform.tfstate" ] || continue
  printf '\n\033[1;34m### destroy tofu/%s\033[0m\n' "$stack"
  tofu -chdir="tofu/$stack" destroy $TF_ARGS || true
done
# Stop floci first: while it runs it restarts the containers below, and
# restores ECR repositories from the registry volume, so a later apply would
# find resources its state does not know about.
docker compose down -v
docker rm -f floci-ecr-registry floci-eks-ai-platform >/dev/null 2>&1
docker ps -aq --filter name=floci-ec2- | xargs -r docker rm -f >/dev/null 2>&1
docker volume ls -q --filter label=floci=true | xargs -r docker volume rm -f >/dev/null 2>&1
docker volume rm -f floci-ecr-registry-data floci-eks-ai-platform >/dev/null 2>&1
rm -rf .state
echo "aws-local removed"
