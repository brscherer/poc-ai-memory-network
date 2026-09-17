#!/usr/bin/env bash
# IAM: an admin user for the local "platform team" (used for EKS auth and
# seeding), plus the instance role + profile EC2 hosts use to read secrets.
. "$(dirname "$0")/lib.sh"

log "IAM admin user"
if [ ! -f "$STATE/admin.env" ]; then
  aws iam create-user --user-name poc-admin >/dev/null 2>&1 || true
  aws iam attach-user-policy --user-name poc-admin \
    --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
  aws iam create-access-key --user-name poc-admin \
    | jq -r '"export AWS_ACCESS_KEY_ID=\(.AccessKey.AccessKeyId)\nexport AWS_SECRET_ACCESS_KEY=\(.AccessKey.SecretAccessKey)"' \
    > "$STATE/admin.env"
  chmod 600 "$STATE/admin.env"
fi
. "$STATE/admin.env"
aws sts get-caller-identity --query Arn --output text

log "EKS cluster role"
aws iam create-role --role-name eks-cluster --assume-role-policy-document \
  '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"eks.amazonaws.com"},"Action":"sts:AssumeRole"}]}' >/dev/null 2>&1 || true

log "EC2 host role + instance profile (read only its own secrets)"
aws iam create-role --role-name ai-host --assume-role-policy-document \
  '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}' >/dev/null 2>&1 || true
aws iam put-role-policy --role-name ai-host --policy-name read-own-secrets --policy-document \
  '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":"secretsmanager:GetSecretValue","Resource":["arn:aws:secretsmanager:*:*:secret:ai-gateway/hosts/*","arn:aws:secretsmanager:*:*:secret:ai-memory/hosts/*"]},{"Effect":"Allow","Action":"s3:GetObject","Resource":"arn:aws:s3:::example-ai-platform-artifacts/ai-memory/*"}]}'
aws iam create-instance-profile --instance-profile-name ai-host >/dev/null 2>&1 || true
aws iam add-role-to-instance-profile --instance-profile-name ai-host --role-name ai-host >/dev/null 2>&1 || true
aws iam list-instance-profiles --query 'InstanceProfiles[].InstanceProfileName' --output text
