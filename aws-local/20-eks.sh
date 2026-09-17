#!/usr/bin/env bash
# EKS: create the shared cluster (k3s under the hood) and a kubeconfig that
# authenticates with `aws eks get-token`, exactly like a real cluster.
. "$(dirname "$0")/lib.sh"

log "EKS cluster $CLUSTER"
aws eks describe-cluster --name "$CLUSTER" >/dev/null 2>&1 || aws eks create-cluster --name "$CLUSTER" \
  --role-arn "arn:aws:iam::${ACCOUNT_ID}:role/eks-cluster" --resources-vpc-config "{}" >/dev/null || true
for i in $(seq 1 90); do
  st=$(aws eks describe-cluster --name "$CLUSTER" --query cluster.status --output text)
  [ "$st" = ACTIVE ] && break; sleep 5
done
echo "status: $st"; [ "$st" = ACTIVE ]

aws eks update-kubeconfig --name "$CLUSTER" --kubeconfig "$KUBECONFIG" >/dev/null
# kubeconfig's exec plugin must reach floci and sign with the admin key.
KUSER=$(kubectl config view -o jsonpath='{.users[0].name}')
kubectl config set-credentials "$KUSER" \
  --exec-env=AWS_ENDPOINT_URL=http://127.0.0.1:4566 \
  --exec-env=AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" \
  --exec-env=AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" >/dev/null
chmod 600 "$KUBECONFIG"
kubectl wait --for=condition=Ready node --all --timeout=180s
kubectl get nodes -o wide
