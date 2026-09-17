#!/usr/bin/env bash
# Bring the whole local AWS architecture up, in order. Every step is
# idempotent. Infrastructure is OpenTofu; the scripts cover what is not an
# AWS API call: local Docker, kustomize, and credentials only the running
# services can issue.
set -euo pipefail
cd "$(dirname "$0")"
TF_ARGS=${TF_ARGS:--auto-approve}

step() { printf '\n\033[1;34m### %s\033[0m\n' "$*"; }

step "floci (emulated AWS)"
docker compose up -d
until curl -sf http://127.0.0.1:4566/_floci/health >/dev/null; do sleep 2; done

step "10-artifacts.sh  — fetch + verify release tarballs"
./10-artifacts.sh

step "tofu/aws         — IAM, secrets, S3, ECR, VPC, EKS"
tofu -chdir=tofu/aws init -input=false >/dev/null
# floci restores ECR repositories from its registry volume, which outlives
# its own data dir, so a repository can exist without being in state. Adopt
# it instead of failing the apply.
if ! tofu -chdir=tofu/aws state show aws_ecr_repository.ai_memory >/dev/null 2>&1 &&
   AWS_ENDPOINT_URL=http://127.0.0.1:4566 AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test \
   AWS_DEFAULT_REGION=us-east-1 aws ecr describe-repositories --repository-names mirror/ai-memory >/dev/null 2>&1; then
  echo "adopting the existing ECR repository into state"
  tofu -chdir=tofu/aws import aws_ecr_repository.ai_memory mirror/ai-memory >/dev/null
fi
tofu -chdir=tofu/aws apply $TF_ARGS

step "20-kubeconfig.sh — admin key + kubeconfig"
./20-kubeconfig.sh

step "30-images.sh     — mirror to ECR, load images into the node"
./30-images.sh

step "tofu/cluster     — AWS endpoint Service, namespaces, credentials"
tofu -chdir=tofu/cluster init -input=false >/dev/null
tofu -chdir=tofu/cluster apply $TF_ARGS \
  -var "cluster_name=$(tofu -chdir=tofu/aws output -raw cluster_name)" \
  -var "cluster_endpoint=$(tofu -chdir=tofu/aws output -raw cluster_endpoint)" \
  -var "cluster_ca=$(tofu -chdir=tofu/aws output -raw cluster_ca)" \
  -var "aws_endpoint_ip=$(docker inspect -f '{{(index .NetworkSettings.Networks "aimem-local").IPAddress}}' aimem-floci)" \
  -var "aws_access_key_id=$(tofu -chdir=tofu/aws output -raw admin_access_key_id)" \
  -var "aws_secret_access_key=$(tofu -chdir=tofu/aws output -raw admin_secret_access_key)"

step "40-platform.sh   — External Secrets + ClusterSecretStore"
./40-platform.sh

step "50-gateway.sh    — LiteLLM"
./50-gateway.sh

step "60-memory.sh     — ai-memory tenant"
./60-memory.sh

step "70-keys.sh       — service, developer and host credentials"
./70-keys.sh

step "tofu/host        — EC2 developer/agent host"
tofu -chdir=tofu/host init -input=false >/dev/null
tofu -chdir=tofu/host apply $TF_ARGS

step "85-ec2-wait.sh   — guest bootstrap"
./85-ec2-wait.sh

printf '\nAll steps done. Run ./90-verify.sh for the evidence report.\n'
