#!/usr/bin/env bash
# ==============================================================================
# deploy-airgap-package.sh
# Deploys the built Zarf package to a target Kubernetes cluster (Kind, K3s, Edge)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

PACKAGE_FILE=$(ls -t "${REPO_ROOT}/build"/zarf-package-tactical-sdn-stack-*.tar.zst 2>/dev/null | head -n 1 || true)

if [ -z "${PACKAGE_FILE}" ] || [ ! -f "${PACKAGE_FILE}" ]; then
  echo "[-] Error: No Zarf package found in ${REPO_ROOT}/build/."
  echo "    Run ./scripts/build-airgap-package.sh first."
  exit 1
fi

echo "==> Deploying Zarf air-gap package: $(basename "${PACKAGE_FILE}")..."
zarf package deploy "${PACKAGE_FILE}" --confirm

echo "==> Verifying tactical-sdn deployment in cluster..."
kubectl get pods -n tactical-sdn -o wide
