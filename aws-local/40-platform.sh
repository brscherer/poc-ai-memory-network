#!/usr/bin/env bash
# Cluster add-ons that a real EKS platform team would already provide:
#   - a stable in-cluster name for the AWS APIs (floci)
#   - External Secrets Operator reading from Secrets Manager
. "$(dirname "$0")/lib.sh"

log "In-cluster route to the AWS APIs"
# Pod DNS cannot see Docker's embedded DNS, so publish floci as a selector-less
# Service backed by its container IP: http://aws.aws-local.svc.cluster.local:4566
FLOCI_IP=$(floci_ip)
kubectl apply -f - <<YAML
apiVersion: v1
kind: Namespace
metadata: { name: aws-local }
---
apiVersion: v1
kind: Service
metadata: { name: aws, namespace: aws-local }
spec:
  ports: [{ name: http, port: 4566, targetPort: 4566 }]
---
apiVersion: discovery.k8s.io/v1
kind: EndpointSlice
metadata:
  name: aws-floci
  namespace: aws-local
  labels: { kubernetes.io/service-name: aws }
addressType: IPv4
ports: [{ name: http, port: 4566, protocol: TCP }]
endpoints: [{ addresses: ["$FLOCI_IP"] }]
YAML
kubectl run aws-probe -n aws-local --rm -i --restart=Never --quiet --image=curlimages/curl:8.10.1 -- \
  -sf --retry 10 --retry-delay 2 --retry-all-errors -o /dev/null \
  -w 'aws endpoint from a pod: HTTP %{http_code}\n' http://aws.aws-local.svc.cluster.local:4566/_floci/health

log "External Secrets Operator"
helm repo add external-secrets https://charts.external-secrets.io >/dev/null 2>&1 || true
helm repo update external-secrets >/dev/null
helm upgrade --install external-secrets external-secrets/external-secrets \
  -n external-secrets --create-namespace --wait --timeout 10m \
  --set installCRDs=true \
  --set 'extraEnv[0].name=AWS_SECRETSMANAGER_ENDPOINT' \
  --set 'extraEnv[0].value=http://aws.aws-local.svc.cluster.local:4566' \
  --set 'extraEnv[1].name=AWS_STS_ENDPOINT' \
  --set 'extraEnv[1].value=http://aws.aws-local.svc.cluster.local:4566' >/dev/null
helm list -n external-secrets

# Static keys stand in for Pod Identity / IRSA, which floci does not emulate.
kubectl -n external-secrets create secret generic aws-credentials \
  --from-literal=access-key="$AWS_ACCESS_KEY_ID" --from-literal=secret-access-key="$AWS_SECRET_ACCESS_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f "$AWS_LOCAL_DIR/k8s/cluster-secret-store.yaml"
kubectl wait --for=condition=Ready clustersecretstore/aws-secrets-manager --timeout=60s
