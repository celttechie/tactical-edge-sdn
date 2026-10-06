#!/usr/bin/env bash
# ==============================================================================
# build-airgap-package.sh
# Automates local image build, Helm validation, and self-contained Zarf packaging
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

TAG="${1:-v0.3.0}"
IMAGE_NAME="tactical-sdn-stack:${TAG}"

echo "==> [1/4] Building hardened local container image: ${IMAGE_NAME}..."
docker build -t "${IMAGE_NAME}" -f "${REPO_ROOT}/src/dataplane/Dockerfile" "${REPO_ROOT}"
docker tag "${IMAGE_NAME}" "docker.io/library/${IMAGE_NAME}"

echo "==> [2/4] Validating Helm chart templates..."
helm lint "${REPO_ROOT}/packages/helm/tactical-sdn"
helm template test "${REPO_ROOT}/packages/helm/tactical-sdn" > /dev/null

echo "==> [3/4] Assembling air-gap Zarf package archive..."
mkdir -p "${REPO_ROOT}/build"
zarf package create "${REPO_ROOT}/packages/zarf" --confirm --output "${REPO_ROOT}/build"

echo "==> [4/4] Package creation successful!"
ls -lh "${REPO_ROOT}/build"/zarf-package-tactical-sdn-stack-*.tar.zst
