#!/usr/bin/env bash
# Tear everything down: the Tofu stacks newest first, then floci and its data.
#
# The cluster stack needs the same cluster variables as `apply`, or its
# provider falls back to localhost and the destroy fails, leaving state that
# describes resources the next run cannot refresh.
set -uo pipefail
cd "$(dirname "$0")"
TF_ARGS=${TF_ARGS:--auto-approve}
have_state() { [ -f "tofu/$1/terraform.tfstate" ] && [ -s "tofu/$1/terraform.tfstate" ]; }
aws_out() { tofu -chdir=tofu/aws output -raw "$1" 2>/dev/null; }

if have_state host; then
  printf '\n\033[1;34m### destroy tofu/host\033[0m\n'
  tofu -chdir=tofu/host destroy $TF_ARGS || true
fi

if have_state cluster; then
  printf '\n\033[1;34m### destroy tofu/cluster\033[0m\n'
  tofu -chdir=tofu/cluster destroy $TF_ARGS \
    -var "cluster_name=$(aws_out cluster_name)" \
    -var "cluster_endpoint=$(aws_out cluster_endpoint)" \
    -var "cluster_ca=$(aws_out cluster_ca)" \
    -var "aws_access_key_id=$(aws_out admin_access_key_id)" \
    -var "aws_secret_access_key=$(aws_out admin_secret_access_key)" || true
fi

if have_state aws; then
  printf '\n\033[1;34m### destroy tofu/aws\033[0m\n'
  tofu -chdir=tofu/aws destroy $TF_ARGS || true
fi

printf '\n\033[1;34m### floci\033[0m\n'
# Stop floci first: while it runs it restarts the containers below, and
# restores ECR repositories from the registry volume, so a later apply would
# find resources its state does not know about.
docker compose down -v
docker rm -f floci-ecr-registry floci-eks-ai-platform >/dev/null 2>&1
docker ps -aq --filter name=floci-ec2- | xargs -r docker rm -f >/dev/null 2>&1
docker volume ls -q --filter label=floci=true | xargs -r docker volume rm -f >/dev/null 2>&1
docker volume rm -f floci-ecr-registry-data floci-eks-ai-platform >/dev/null 2>&1

# Everything the state described lives in the volumes just removed, so any
# leftover state would only describe resources that no longer exist. (On real
# AWS you would never do this: the state is the record of what you own.)
rm -f tofu/*/terraform.tfstate tofu/*/terraform.tfstate.backup
rm -rf .state
echo "aws-local removed"
