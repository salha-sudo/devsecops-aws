#!/usr/bin/env bash
# Usage:
#   GITHUB_OWNER=monuser GITHUB_REPO=devsecops-aws EMAIL=moi@mail.com ./scripts/deploy.sh
# Options: AWS_REGION (def. eu-west-3), STACK_NAME (def. devsecops-pipeline),
#          ENABLE_INSPECTOR=true|false, ENABLE_BASELINE=true|false
set -euo pipefail

: "${GITHUB_OWNER:?definir GITHUB_OWNER}"
: "${GITHUB_REPO:?definir GITHUB_REPO}"
: "${EMAIL:?definir EMAIL}"
export AWS_REGION="${AWS_REGION:-eu-west-3}"
export AWS_DEFAULT_REGION="$AWS_REGION"
STACK="${STACK_NAME:-devsecops-pipeline}"
BRANCH="${GITHUB_BRANCH:-main}"

echo ">> Compte: $(aws sts get-caller-identity --query Account --output text) | Region: $AWS_REGION"

VPC_ID=$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text)
if [ "$VPC_ID" = "None" ]; then echo "Pas de VPC par defaut : definir VPC_ID et SUBNETS manuellement"; exit 1; fi
SUBNETS="${SUBNETS:-$(aws ec2 describe-subnets --filters Name=vpc-id,Values="$VPC_ID" --query 'Subnets[0:2].SubnetId' --output text | tr '\t' ',')}"
echo ">> VPC $VPC_ID | Subnets $SUBNETS"

echo ">> Deploiement du pipeline..."
aws cloudformation deploy \
  --template-file infra/pipeline.yaml \
  --stack-name "$STACK" \
  --capabilities CAPABILITY_IAM \
  --no-fail-on-empty-changeset \
  --parameter-overrides \
    GitHubOwner="$GITHUB_OWNER" GitHubRepo="$GITHUB_REPO" GitHubBranch="$BRANCH" \
    NotificationEmail="$EMAIL" VpcId="$VPC_ID" SubnetIds="$SUBNETS"

if [ "${ENABLE_INSPECTOR:-true}" = "true" ]; then
  echo ">> Activation Amazon Inspector + scan ECR renforce (continu)..."
  aws inspector2 enable --resource-types ECR >/dev/null || echo "   (Inspector: activation impossible, a faire manuellement)"
  aws ecr put-registry-scanning-configuration --scan-type ENHANCED \
    --rules '[{"scanFrequency":"CONTINUOUS_SCAN","repositoryFilters":[{"filter":"*","filterType":"WILDCARD"}]}]' >/dev/null \
    || echo "   (ECR enhanced scanning: a configurer manuellement)"
fi

if [ "${ENABLE_BASELINE:-false}" = "true" ]; then
  echo ">> GuardDuty + Security Hub..."
  aws cloudformation deploy --template-file infra/security-baseline.yaml \
    --stack-name "${STACK}-baseline" --no-fail-on-empty-changeset
fi

CONN=$(aws cloudformation describe-stacks --stack-name "$STACK" --query "Stacks[0].Outputs[?OutputKey=='ConnectionArn'].OutputValue" --output text)
cat <<MSG

==================== ACTIONS MANUELLES ====================
1. Confirmer l'abonnement SNS recu par email ($EMAIL).
2. Autoriser la connexion GitHub (obligatoire, une seule fois) :
   https://${AWS_REGION}.console.aws.amazon.com/codesuite/settings/connections
   -> ouvrir la connexion "${STACK}-gh" (PENDING) -> "Update pending connection" -> installer l'app GitHub.
   ARN: $CONN
3. Console CodePipeline -> "$STACK" -> "Release change".
===========================================================
MSG
