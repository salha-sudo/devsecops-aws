#!/usr/bin/env bash
# Supprime tout (apps, pipeline, ECR, artefacts).
set -euo pipefail
export AWS_REGION="${AWS_REGION:-eu-west-3}" AWS_DEFAULT_REGION="${AWS_REGION:-eu-west-3}"
STACK="${STACK_NAME:-devsecops-pipeline}"

for env in prod staging; do
  echo ">> Suppression ${STACK}-app-${env}"
  aws cloudformation delete-stack --stack-name "${STACK}-app-${env}" || true
  aws cloudformation wait stack-delete-complete --stack-name "${STACK}-app-${env}" || true
done

BUCKET=$(aws cloudformation describe-stacks --stack-name "$STACK" --query "Stacks[0].Outputs[?OutputKey=='ArtifactBucket'].OutputValue" --output text)
echo ">> Vidage du bucket $BUCKET"
aws s3 rm "s3://$BUCKET" --recursive || true

echo ">> Suppression du pipeline"
aws cloudformation delete-stack --stack-name "$STACK"
aws cloudformation wait stack-delete-complete --stack-name "$STACK"
aws cloudformation delete-stack --stack-name "${STACK}-baseline" 2>/dev/null || true
echo "Termine. (La cle KMS reste en 'pending deletion' 7-30 jours, sans cout notable.)"
