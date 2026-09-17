#!/usr/bin/env bash
# Secrets Manager, S3 and ECR: the AWS resources the platform depends on.
. "$(dirname "$0")/lib.sh"

log "Secrets Manager (random values, created once)"
for s in ai-gateway/litellm/master-key ai-gateway/litellm/salt-key ai-gateway/litellm/db-password \
         ai-memory/$TENANT/root-token ai-memory/$TENANT/token-pepper ai-memory/$TENANT/recovery-token; do
  ensure_secret "$s"
done
# LiteLLM keys are prefixed sk- by convention.
v=$(aws secretsmanager get-secret-value --secret-id ai-gateway/litellm/master-key --query SecretString --output text)
case "$v" in sk-*) ;; *) put_secret ai-gateway/litellm/master-key "sk-$v" ;; esac
# Placeholder until 70-keys.sh issues the real LiteLLM service key.
aws secretsmanager describe-secret --secret-id ai-memory/$TENANT/litellm-key >/dev/null 2>&1 \
  || put_secret ai-memory/$TENANT/litellm-key pending-bootstrap
# Static AWS credentials the in-cluster backup shipper uses against floci
# (stand-in for EKS Pod Identity, which floci does not emulate).
put_secret ai-memory/$TENANT/backup-aws "$(jq -nc --arg a "$AWS_ACCESS_KEY_ID" --arg s "$AWS_SECRET_ACCESS_KEY" '{access_key:$a,secret_key:$s}')"
aws secretsmanager list-secrets --query 'SecretList[].Name' --output text | tr '\t' '\n'

log "S3 backup bucket"
aws s3api head-bucket --bucket "$BACKUP_BUCKET" 2>/dev/null || aws s3api create-bucket --bucket "$BACKUP_BUCKET" >/dev/null
aws s3api put-bucket-versioning --bucket "$BACKUP_BUCKET" --versioning-configuration Status=Enabled
aws s3api get-bucket-versioning --bucket "$BACKUP_BUCKET" --query Status --output text

log "Artifact bucket with the ai-memory release tarballs"
aws s3api head-bucket --bucket "$ARTIFACTS_BUCKET" 2>/dev/null || aws s3api create-bucket --bucket "$ARTIFACTS_BUCKET" >/dev/null
VER="${AI_MEMORY_VERSION:-2.2.1}"
mkdir -p "$STATE/cache"
for arch in aarch64 x86_64; do
  f="ai-memory-linux-$arch.tar.gz"
  if ! aws s3api head-object --bucket "$ARTIFACTS_BUCKET" --key "ai-memory/$VER/$f" >/dev/null 2>&1; then
    [ -f "$STATE/cache/$f" ] || curl -fsSL -o "$STATE/cache/$f" "https://github.com/akitaonrails/ai-memory/releases/download/v$VER/$f"
    curl -fsSL "https://github.com/akitaonrails/ai-memory/releases/download/v$VER/$f.sha256" | awk '{print $1}' > "$STATE/cache/$f.sha256"
    [ "$(shasum -a 256 "$STATE/cache/$f" | awk '{print $1}')" = "$(cat "$STATE/cache/$f.sha256")" ] || { echo "checksum mismatch: $f"; exit 1; }
    aws s3 cp "$STATE/cache/$f" "s3://$ARTIFACTS_BUCKET/ai-memory/$VER/$f" --only-show-errors
  fi
done
aws s3 ls "s3://$ARTIFACTS_BUCKET/ai-memory/$VER/"

log "ECR mirror of the ai-memory image"
aws ecr describe-repositories --repository-names mirror/ai-memory >/dev/null 2>&1 \
  || aws ecr create-repository --repository-name mirror/ai-memory --image-tag-mutability IMMUTABLE >/dev/null
docker image inspect "$AI_MEMORY_IMAGE_SRC" >/dev/null 2>&1 || docker pull -q "$AI_MEMORY_IMAGE_SRC"
TAG="$(docker run --rm --entrypoint ai-memory "$AI_MEMORY_IMAGE_SRC" --version | awk '{print $2}')"
MIRROR="$ECR_HOST/mirror/ai-memory:$TAG"
aws ecr get-login-password | docker login -u AWS --password-stdin "$ECR_HOST" >/dev/null
docker tag "$AI_MEMORY_IMAGE_SRC" "$MIRROR"
if ! aws ecr describe-images --repository-name mirror/ai-memory --image-ids imageTag="$TAG" >/dev/null 2>&1; then
  docker push -q "$MIRROR"
fi
DIGEST=$(aws ecr describe-images --repository-name mirror/ai-memory --image-ids imageTag="$TAG" \
  --query 'imageDetails[0].imageDigest' --output text)
echo "$MIRROR -> $DIGEST"
printf 'AI_MEMORY_MIRROR=%s\nAI_MEMORY_TAG=%s\nAI_MEMORY_DIGEST=%s\n' "$ECR_HOST/mirror/ai-memory" "$TAG" "$DIGEST" > "$STATE/image.env"

log "Load the mirrored image into the EKS node"
# The k3s node cannot resolve *.localhost to floci, so the image is imported
# under its ECR name; pods reference that name with imagePullPolicy: Never.
docker save "$MIRROR" | docker exec -i "floci-eks-$CLUSTER" ctr -a /run/k3s/containerd/containerd.sock -n k8s.io images import - >/dev/null
docker exec "floci-eks-$CLUSTER" ctr -a /run/k3s/containerd/containerd.sock -n k8s.io images ls -q | grep mirror/ai-memory
