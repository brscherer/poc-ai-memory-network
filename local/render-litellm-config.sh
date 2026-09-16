#!/usr/bin/env bash
# Render litellm-config.tmpl.yaml with the Bedrock IDs from .env.
set -euo pipefail
cd "$(dirname "$0")"
set -a; . ./.env; set +a
envsubst '${BEDROCK_OPUS_ID} ${BEDROCK_SONNET_ID} ${BEDROCK_HAIKU_ID} ${BEDROCK_EMBED_ID}' \
  < litellm-config.tmpl.yaml > litellm-config.rendered.yaml
echo "wrote litellm-config.rendered.yaml"
