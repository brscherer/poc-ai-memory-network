#!/usr/bin/env bash
# Helm installs: External Secrets and the ClusterSecretStore.
#
# Not OpenTofu, and not because of Helm: floci accepts an `aws eks get-token`
# credential for 60 seconds, while a provider resolves its token once per
# apply. A chart install that waits for rollout outlives that token and fails
# with Unauthorized. The CLI re-authenticates per call.
. "$(dirname "$0")/lib.sh"
AWS_URL="$(tofu_out cluster aws_service_url)"

log "External Secrets Operator"
helm repo add external-secrets https://charts.external-secrets.io >/dev/null 2>&1 || true
helm repo update external-secrets >/dev/null
helm upgrade --install external-secrets external-secrets/external-secrets \
  -n external-secrets --wait --timeout 15m \
  --set installCRDs=true \
  --set "extraEnv[0].name=AWS_SECRETSMANAGER_ENDPOINT" \
  --set "extraEnv[0].value=$AWS_URL" \
  --set "extraEnv[1].name=AWS_STS_ENDPOINT" \
  --set "extraEnv[1].value=$AWS_URL" >/dev/null
helm list -n external-secrets

log "ClusterSecretStore"
helm upgrade --install secret-store "$AWS_LOCAL_DIR/tofu/cluster/charts/secret-store" \
  -n external-secrets --wait --timeout 5m \
  --set region="$AWS_DEFAULT_REGION" >/dev/null
kubectl wait --for=condition=Ready clustersecretstore/aws-secrets-manager --timeout=120s
