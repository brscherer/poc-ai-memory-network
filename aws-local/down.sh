#!/usr/bin/env bash
# Tear everything down: EC2 guests, the EKS cluster, floci and its data.
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh 2>/dev/null
ids=$(aws ec2 describe-instances --query 'Reservations[].Instances[].InstanceId' --output text 2>/dev/null)
[ -n "$ids" ] && aws ec2 terminate-instances --instance-ids $ids >/dev/null
aws eks delete-cluster --name "$CLUSTER" >/dev/null 2>&1
sleep 5
docker compose down -v
docker rm -f floci-ecr-registry "floci-eks-$CLUSTER" >/dev/null 2>&1
rm -rf .state
echo "aws-local removed"
