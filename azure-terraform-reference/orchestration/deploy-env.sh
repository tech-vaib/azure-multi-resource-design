#!/usr/bin/env bash
set -euo pipefail

# Reference orchestration. Supply backend config and subscription authentication
# via the approved CI/CD pipeline. Edit stage order for the actual dependency graph.
# Usage: ./orchestration/deploy-env.sh dev app1

SUBSCRIPTION="${1:?subscription required}"
ENVIRONMENT="${2:?environment required}"

BASE="live/subscriptions/${SUBSCRIPTION}"
ENV="${BASE}/environments/${ENVIRONMENT}"

STAGES=(
  "${BASE}/shared/00-network-foundation"
  "${BASE}/shared/01-shared-compute"
  "${BASE}/shared/02-shared-platform"
  "${ENV}/20-aks"
  "${ENV}/30-ingress"
  "${ENV}/40-apim"
  "${ENV}/50-cosmos"
  "${ENV}/51-postgresql"
  "${ENV}/52-redis"
  "${ENV}/53-service-bus"
  "${ENV}/90-app-infrastructure"
)

for DIR in "${STAGES[@]}"; do
  [[ -d "${DIR}" ]] || { echo "Skip missing optional stage: ${DIR}"; continue; }
  echo "===== ${DIR} ====="
  terraform -chdir="${DIR}" init
  terraform -chdir="${DIR}" validate
  terraform -chdir="${DIR}" plan -out=tfplan
  read -r -p "Apply this reviewed plan? Type yes: " OK
  [[ "${OK}" == "yes" ]] || exit 1
  terraform -chdir="${DIR}" apply tfplan
done
