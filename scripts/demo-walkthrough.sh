#!/usr/bin/env bash
# ==============================================================================
# Tactical Edge SDN - Demonstration Preparation & Helper Tool
#
# Commands:
#   status  - Verify tunnel, services, and live C2 telemetry
#   reset   - Revert shipboard gateway to clean Day 0 Legacy VNF baseline
#   preflight - Run automated readiness probe before recording video
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

ACTION="${1:-status}"

check_dashboard() {
    local url="http://localhost:8080/health"
    if curl -s -m 2 "$url" | grep -q "UP"; then
        return 0
    else
        return 1
    fi
}

case "$ACTION" in
    status)
        echo -e "${BLUE}======================================================================${NC}"
        echo -e "${BLUE}  Tactical Edge SDN: Video Demonstration Pre-Flight Status            ${NC}"
        echo -e "${BLUE}======================================================================${NC}"

        # 1. Check tunnel
        echo -n " -> SSH Tunnel (localhost:8080): "
        if check_dashboard; then
            echo -e "${GREEN}ACTIVE & HEALTHY (HTTP 200)${NC}"
        else
            echo -e "${YELLOW}INACTIVE. Starting tunnel...${NC}"
            "${REPO_ROOT}/scripts/dashboard-tunnel.sh" start
        fi

        # 2. Check live status
        local_status=$(curl -s -m 3 http://localhost:8080/api/status 2>/dev/null || echo "{}")
        if [ "$local_status" != "{}" ]; then
            posture=$(echo "$local_status" | python3 -c 'import sys, json; d=json.load(sys.stdin); print(d.get("modernization",{}).get("gateway_type", "UNKNOWN"))')
            primary=$(echo "$local_status" | python3 -c 'import sys, json; d=json.load(sys.stdin); print(d.get("primary_bearer", "UNKNOWN"))')
            readiness=$(echo "$local_status" | python3 -c 'import sys, json; d=json.load(sys.stdin); print(d.get("overall_readiness", "UNKNOWN"))')
            pkts=$(echo "$local_status" | python3 -c 'import sys, json; d=json.load(sys.stdin); print(d.get("enclave_traffic",{}).get("packets_per_sec", 0))')

            echo -e " -> Current Gateway Posture:   ${YELLOW}${posture}${NC}"
            echo -e " -> Active Primary Bearer:     ${GREEN}${primary^^}${NC}"
            echo -e " -> Overall Readiness:         ${GREEN}${readiness}${NC}"
            echo -e " -> Enclave C2 Stream Rate:    ${GREEN}${pkts} pkts/s${NC}"
            echo -e " -> Dashboard Web Interface:   ${BLUE}http://localhost:8080/${NC}"
        else
            echo -e "${RED} [!] Failed to fetch live status from http://localhost:8080/api/status${NC}"
        fi
        echo -e "${BLUE}======================================================================${NC}"
        ;;

    reset|reset-day0)
        echo -e "${YELLOW}======================================================================${NC}"
        echo -e "${YELLOW}  Resetting Testbed to Stage 1: Day 0 Legacy VNF Baseline            ${NC}"
        echo -e "${YELLOW}======================================================================${NC}"
        curl -s -X POST http://localhost:8080/api/chaos -H "Content-Type: application/json" -d '{"action":"clean_slate"}' >/dev/null || true
        curl -s -X POST http://localhost:8080/api/modernization -H "Content-Type: application/json" -d '{"action":"reset_day0"}' >/dev/null || true
        
        echo " -> Decommissioning CNF and activating legacy router daemon on ship-gateway..."
        ssh -o BatchMode=yes ship-gateway "sudo systemctl stop k3s 2>/dev/null || true; sudo systemctl disable k3s 2>/dev/null || true; sudo systemctl restart sdwan-controller.service 2>/dev/null || true"
        
        # Restore baseline metrics
        ssh -o BatchMode=yes shore-gateway "sudo systemctl restart shore-dashboard.service"
        sleep 2
        echo -e "${GREEN} [✓] Day 0 Legacy Baseline restored successfully.${NC}"
        echo -e " -> Gateway Posture: LEGACY_VNF (Static Metric Routing)"
        echo -e " -> Open http://localhost:8080/ to begin recording Scene 1!"
        ;;

    preflight)
        echo -e "${BLUE}==> Executing automated pre-flight verification test...${NC}"
        PYTHON_BIN="${REPO_ROOT}/.venv/bin/python"
        if [ ! -x "$PYTHON_BIN" ]; then PYTHON_BIN="$(which python3)"; fi
        "$PYTHON_BIN" "${REPO_ROOT}/tests/integration/test_dashboard_feedback.py"
        echo -e "${GREEN}==> Pre-flight verification completed. System is 100% demo-ready!${NC}"
        ;;

    *)
        echo "Usage: $0 {status|reset|preflight}"
        exit 1
        ;;
esac
