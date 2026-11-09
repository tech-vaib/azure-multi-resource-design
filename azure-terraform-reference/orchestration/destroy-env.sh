#!/usr/bin/env bash
set -euo pipefail

# Intentionally conservative reference. It only destroys explicitly supplied
# environment state directories, in reverse dependency order. Shared states are
# excluded. Review plans and use protected CI/CD approvals for production.
# Usage: ./orchestration/destroy-env.sh live/subscriptions/dev/environments/app1/90-app-infrastructure ...

if [[ "$#" -lt 1 ]]; then
  echo "Pass one or more exact Terraform root directories to destroy."
  exit 2
fi

for DIR in "$@"; do
  [[ -d "${DIR}" ]] || { echo "Missing directory: ${DIR}"; exit 1; }
  echo "===== Destroy plan: ${DIR} ====="
  terraform -chdir="${DIR}" init
  terraform -chdir="${DIR}" plan -destroy -out=tf-destroy-plan
  read -r -p "Apply this destroy plan for ${DIR}? Type DESTROY: " OK
  [[ "${OK}" == "DESTROY" ]] || { echo "Stopped."; exit 1; }
  terraform -chdir="${DIR}" apply tf-destroy-plan
done
