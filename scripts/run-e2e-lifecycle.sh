#!/usr/bin/env bash
# ==============================================================================
# Tactical Edge SDN - End-to-End Autonomous Lifecycle Orchestrator
#
# Fully automated, declarative verification of the entire project lifecycle:
# 1. Teardown existing sandbox topology (tofu destroy)
# 2. Deploy fresh legacy baseline sandbox topology (tofu apply)
#    - Blocks on OpenTofu `wait_for_convergence` barrier (cloud-init & SSH readiness)
# 3. Validate Milestone 1: Legacy static routing baseline and DDIL failure mode
# 4. Modernize shipboard node to K3s + Zarf CNF (modernize-ship-node.sh)
#    - Blocks on node ready, Zarf registry ready, DaemonSet ready, and verification
# 5. Validate Milestone 2: Dynamic SD-WAN SLA steering and failover
# 6. Validate Milestone 4: Lula OSCAL continuous compliance against NIST SP 800-53
# 7. Run DDIL chaos resilience benchmark
#
# Returns 0 only if all phases pass without manual intervention.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Color formatting
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_step() {
    echo -e "\n${BLUE}======================================================================${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}======================================================================${NC}"
}

cd "${REPO_ROOT}"

START_TIME=$(date +%s)

# ------------------------------------------------------------------------------
# Phase 1: Clean Slate Teardown
# ------------------------------------------------------------------------------
log_step "[Phase 1/7] Tearing down any existing ephemeral sandbox VMs..."
"${REPO_ROOT}/scripts/tofu-sandbox.sh" destroy -auto-approve

# ------------------------------------------------------------------------------
# Phase 2: Deploy Declarative Infrastructure & Await Convergence
# ------------------------------------------------------------------------------
log_step "[Phase 2/7] Deploying sandbox topology with OpenTofu convergence barrier..."
"${REPO_ROOT}/scripts/tofu-sandbox.sh" apply -auto-approve

# ------------------------------------------------------------------------------
# Phase 3: Milestone 1 - Legacy Routing Baseline Verification
# ------------------------------------------------------------------------------
log_step "[Phase 3/7] Running Milestone 1: Legacy Routing Baseline & Failure Tests..."
python3 "${REPO_ROOT}/tests/integration/test_legacy_baseline.py"

# ------------------------------------------------------------------------------
# Phase 4: Modernize Ship Gateway to Cloud-Native CNF
# ------------------------------------------------------------------------------
log_step "[Phase 4/7] Modernizing ship-gateway to K3s and deploying Zarf CNF package..."
"${REPO_ROOT}/scripts/modernize-ship-node.sh" ship-gateway

# ------------------------------------------------------------------------------
# Phase 5: Milestone 2 - SD-WAN Failover & Path Steering Verification
# ------------------------------------------------------------------------------
log_step "[Phase 5/7] Running Milestone 2: SD-WAN Dynamic Failover & SLA Tests..."
python3 "${REPO_ROOT}/tests/integration/test_sdn_failover.py"

# ------------------------------------------------------------------------------
# Phase 6: Milestone 4 - Automated Continuous Compliance (Lula OSCAL)
# ------------------------------------------------------------------------------
log_step "[Phase 6/7] Running Milestone 4: Lula OSCAL Automated Compliance Suite..."
python3 -m unittest "${REPO_ROOT}/tests/integration/test_lula_compliance.py"

# ------------------------------------------------------------------------------
# Phase 7: Quantitative DDIL Chaos Resiliency Benchmark
# ------------------------------------------------------------------------------
log_step "[Phase 7/7] Running DDIL Chaos Engineering & Convergence Resiliency Benchmark..."
python3 "${REPO_ROOT}/tests/chaos/run_resiliency_benchmark.py"

END_TIME=$(date +%s)
TOTAL_DURATION=$((END_TIME - START_TIME))

echo -e "\n${GREEN}======================================================================${NC}"
echo -e "${GREEN}  [COMPLETE] End-to-End Lifecycle Executed Successfully in ${TOTAL_DURATION}s!  ${NC}"
echo -e "${GREEN}  All declarative barriers, deployments, and tests passed autonomously.${NC}"
echo -e "${GREEN}======================================================================${NC}\n"
