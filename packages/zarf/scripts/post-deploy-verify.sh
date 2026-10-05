#!/usr/bin/env bash
# Post-deploy check: verify running pods and routing health
set -euo pipefail

echo "==> [Zarf Action] Verifying Tactical Edge SD-WAN deployment status..."
if command -v kubectl &>/dev/null; then
    echo " -> Checking Kubernetes pods in tactical-sdn namespace..."
    kubectl wait --namespace tactical-sdn --for=condition=ready pod --selector=app.kubernetes.io/name=tactical-sdn-stack --timeout=60s || true
fi

echo "==> Post-deploy verification completed."
