# Shared settings for the aws-local scripts. Source, don't execute.
set -euo pipefail
AWS_LOCAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$AWS_LOCAL_DIR/.." && pwd)"
STATE="$AWS_LOCAL_DIR/.state"
mkdir -p "$STATE"

export AWS_ENDPOINT_URL=http://127.0.0.1:4566
export AWS_DEFAULT_REGION=us-east-1
export AWS_PAGER=""
ACCOUNT_ID=000000000000
CLUSTER=ai-platform
NETWORK=aimem-local
TENANT=team-a
BACKUP_BUCKET=example-ai-memory-backups
ARTIFACTS_BUCKET=example-ai-platform-artifacts
ECR_HOST="${ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.localhost:4566"
AI_MEMORY_IMAGE_SRC="${AI_MEMORY_IMAGE_SRC:-docker.io/akitaonrails/ai-memory:latest}"
export KUBECONFIG="$STATE/kubeconfig"

# Bootstrap calls use floci's permissive static credentials; everything
# after admin creation uses the IAM admin key (EKS rejects test/test).
if [ -f "$STATE/admin.env" ]; then . "$STATE/admin.env"; else
  export AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test; fi

log()  { printf '\n\033[1m== %s\033[0m\n' "$*"; }
floci_ip() { docker inspect -f "{{(index .NetworkSettings.Networks \"$NETWORK\").IPAddress}}" aimem-floci; }
network_cidr() { docker network inspect -f '{{(index .IPAM.Config 0).Subnet}}' "$NETWORK"; }
# put_secret NAME VALUE : create or update a Secrets Manager secret
put_secret() {
  aws secretsmanager create-secret --name "$1" --secret-string "$2" >/dev/null 2>&1 \
    || aws secretsmanager put-secret-value --secret-id "$1" --secret-string "$2" >/dev/null
}
# ensure_secret NAME : create with a random value only if missing
ensure_secret() {
  aws secretsmanager describe-secret --secret-id "$1" >/dev/null 2>&1 || put_secret "$1" "$(openssl rand -hex 32)"
}
# preload_image IMAGE : pull on the host (cached) and import into the EKS node,
# so pods start fast with imagePullPolicy: IfNotPresent.
preload_image() {
  docker exec "floci-eks-$CLUSTER" ctr -a /run/k3s/containerd/containerd.sock -n k8s.io images ls -q | grep -qx "$1" && return 0
  docker image inspect "$1" >/dev/null 2>&1 || docker pull -q "$1" >/dev/null
  docker save "$1" | docker exec -i "floci-eks-$CLUSTER" ctr -a /run/k3s/containerd/containerd.sock -n k8s.io images import - >/dev/null
  echo "preloaded $1"
}
# port_forward NS SVC LOCAL REMOTE : background port-forward, killed on exit
port_forward() {
  kubectl -n "$1" port-forward "svc/$2" "$3:$4" >/dev/null 2>&1 &
  PF_PIDS="${PF_PIDS:-} $!"
  trap 'kill $PF_PIDS 2>/dev/null || true' EXIT
  for _ in $(seq 1 30); do nc -z 127.0.0.1 "$3" 2>/dev/null && return 0; sleep 1; done
  echo "port-forward $2 failed" >&2; return 1
}
secret_value() { aws secretsmanager get-secret-value --secret-id "$1" --query SecretString --output text; }
has_secret()   { aws secretsmanager describe-secret --secret-id "$1" >/dev/null 2>&1; }
mem_exec()     { kubectl -n ai-memory-team-a exec -i ai-memory-0 -c ai-memory -- ai-memory "$@"; }
