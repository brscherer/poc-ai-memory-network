#!/usr/bin/env bash
# Bring the whole local AWS architecture up, in order. Every step is idempotent.
set -euo pipefail
cd "$(dirname "$0")"
docker compose up -d
until curl -sf http://127.0.0.1:4566/_floci/health >/dev/null; do sleep 2; done
for step in 10-iam 20-eks 30-seed 40-platform 50-gateway 60-memory 70-keys 80-ec2; do
  printf '\n\033[1;34m### %s\033[0m\n' "$step"
  "./$step.sh"
done
printf '\nAll steps done. Run ./90-verify.sh for the evidence report.\n'
