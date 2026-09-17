#!/usr/bin/env bash
# Turn the Tofu outputs into the credentials the later steps use: the admin
# key (floci's EKS webhook rejects the shared test keys) and a kubeconfig
# that authenticates with `aws eks get-token`, exactly like real EKS.
. "$(dirname "$0")/lib.sh"

log "Admin credentials from tofu/aws"
{
  echo "export AWS_ACCESS_KEY_ID=$(tofu_out aws admin_access_key_id)"
  echo "export AWS_SECRET_ACCESS_KEY=$(tofu_out aws admin_secret_access_key)"
} > "$STATE/admin.env"
chmod 600 "$STATE/admin.env"
. "$STATE/admin.env"
aws sts get-caller-identity --query Arn --output text

log "kubeconfig for $(tofu_out aws cluster_name)"
aws eks update-kubeconfig --name "$(tofu_out aws cluster_name)" --kubeconfig "$KUBECONFIG" >/dev/null
KUSER=$(kubectl config view -o jsonpath='{.users[0].name}')
kubectl config set-credentials "$KUSER" \
  --exec-env=AWS_ENDPOINT_URL="$AWS_ENDPOINT_URL" \
  --exec-env=AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" \
  --exec-env=AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" >/dev/null
chmod 600 "$KUBECONFIG"
kubectl wait --for=condition=Ready node --all --timeout=300s
kubectl get nodes
