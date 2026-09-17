#!/usr/bin/env bash
# Container images: mirror ai-memory into the ECR repository Tofu created,
# then load the images the cluster needs into the node. Stays a script
# because it drives the local Docker daemon, not the AWS API.
. "$(dirname "$0")/lib.sh"
CLUSTER="$(tofu_out aws cluster_name)"
REPO="$(tofu_out aws ecr_repository_url)"
ECR_HOST="${REPO%%/*}"

log "Mirror ai-memory into ECR"
docker image inspect "$AI_MEMORY_IMAGE_SRC" >/dev/null 2>&1 || docker pull -q "$AI_MEMORY_IMAGE_SRC" >/dev/null
TAG="$(docker run --rm --entrypoint ai-memory "$AI_MEMORY_IMAGE_SRC" --version | awk '{print $2}')"
MIRROR="$REPO:$TAG"
aws ecr get-login-password | docker login -u AWS --password-stdin "$ECR_HOST" >/dev/null
docker tag "$AI_MEMORY_IMAGE_SRC" "$MIRROR"
aws ecr describe-images --repository-name mirror/ai-memory --image-ids imageTag="$TAG" >/dev/null 2>&1 \
  || docker push -q "$MIRROR" >/dev/null
DIGEST=$(aws ecr describe-images --repository-name mirror/ai-memory --image-ids imageTag="$TAG" \
  --query 'imageDetails[0].imageDigest' --output text)
printf 'AI_MEMORY_MIRROR=%s\nAI_MEMORY_TAG=%s\nAI_MEMORY_DIGEST=%s\n' "$REPO" "$TAG" "$DIGEST" > "$STATE/image.env"
echo "$MIRROR -> $DIGEST"

log "Load images into the EKS node"
# The node cannot resolve *.localhost to floci, so the mirrored image is
# imported under its ECR name and pods use imagePullPolicy: Never.
docker save "$MIRROR" | docker exec -i "floci-eks-$CLUSTER" ctr -a /run/k3s/containerd/containerd.sock -n k8s.io images import - >/dev/null
for img in docker.io/library/postgres:16-alpine ghcr.io/berriai/litellm:main-stable public.ecr.aws/aws-cli/aws-cli:2.17.0 curlimages/curl:8.10.1; do
  preload_image "$img"
done
docker exec "floci-eks-$CLUSTER" ctr -a /run/k3s/containerd/containerd.sock -n k8s.io images ls -q | grep -c . | xargs echo "images on node:"
