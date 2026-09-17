#!/usr/bin/env bash
# ai-memory tenant team-a from the production base + local overlay.
. "$(dirname "$0")/lib.sh"

log "Preload sidecar image"
preload_image public.ecr.aws/aws-cli/aws-cli:2.17.0

log "Deploy ai-memory (team-a)"
kubectl kustomize "$AWS_LOCAL_DIR/k8s/ai-memory" \
  | sed -e "s#VPC_CIDR#$(network_cidr)#" -e "s#S3_ENDPOINT_CIDR#$(floci_ip)/32#" \
  | kubectl apply -f -
kubectl -n ai-memory-team-a wait --for=condition=Ready externalsecret/ai-memory --timeout=120s
kubectl -n ai-memory-team-a rollout status statefulset/ai-memory --timeout=5m
kubectl -n ai-memory-team-a get pods,svc,networkpolicy
