#!/usr/bin/env bash
# LiteLLM gateway (ai-gateway namespace) -> Bedrock Runtime (floci).
. "$(dirname "$0")/lib.sh"

log "Preload gateway images"
preload_image docker.io/library/postgres:16-alpine
preload_image ghcr.io/berriai/litellm:main-stable

log "Deploy LiteLLM"
kubectl apply -k "$AWS_LOCAL_DIR/k8s/ai-gateway"
kubectl -n ai-gateway wait --for=condition=Ready externalsecret/litellm --timeout=120s
kubectl -n ai-gateway rollout status statefulset/litellm-db --timeout=5m
kubectl -n ai-gateway rollout status deployment/litellm --timeout=10m
kubectl -n ai-gateway get pods
