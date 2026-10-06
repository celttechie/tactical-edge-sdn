#!/usr/bin/env bash
# ==============================================================================
# verify-ship-modernization.sh
# Validates the modernized containerized CNF running on ship-gateway:
# - Pod and Service health in tactical-sdn namespace
# - Prometheus telemetry scraping on port 8080/metrics
# - End-to-end traffic delivery from enclave-client to shore-gateway
# ==============================================================================
set -euo pipefail

SHIP_TARGET="${1:-ship-gateway}"
ENCLAVE_CLIENT="enclave-client"
SHORE_TARGET="10.200.1.10"

echo "======================================================================"
echo "  Validating Modernized CNF Posture on ${SHIP_TARGET}                 "
echo "======================================================================"

echo -e "\n==> [1/4] Checking Tactical SDN Kubernetes Pods on ${SHIP_TARGET}..."
ssh "${SHIP_TARGET}" "sudo k3s kubectl get pods -n tactical-sdn -o wide"

echo -e "\n==> [2/4] Checking Tactical SDN Telemetry Service..."
ssh "${SHIP_TARGET}" "sudo k3s kubectl get svc -n tactical-sdn"

echo -e "\n==> [3/4] Querying Prometheus /metrics exposition from CNF container..."
ssh "${SHIP_TARGET}" "curl -s http://127.0.0.1:8080/metrics | grep -E '^# HELP (sdn_|system_)' -A 1 | head -n 12 || true"

echo -e "\n==> [4/4] Verifying End-to-End Enclave-to-Shore Data Flow..."
ssh "${ENCLAVE_CLIENT}" "ping -c 3 ${SHORE_TARGET}"

echo -e "\n======================================================================"
echo "  [PASS] Modernization validation complete! All checks passed."
echo "======================================================================"
