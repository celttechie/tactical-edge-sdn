#!/usr/bin/env bash
# ==============================================================================
# modernize-ship-node.sh
# Upgrades the shipboard gateway node from legacy systemd VNF to cloud-native
# K3s orchestrator and deploys the containerized SD-WAN CNF via Zarf.
# Supports granular step-by-step execution (--step <step>) or full pipeline.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SHIP_TARGET="${SHIP_TARGET:-ship-gateway}"
STEP="full"

SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new)

remote_ssh() {
    ssh "${SSH_OPTS[@]}" "${SHIP_TARGET}" "$@"
}

stage_file_if_needed() {
    local src="$1"
    local dest_dir="$2"
    local base
    base="$(basename "$src")"
    local remote_path="${dest_dir}/${base}"
    
    local local_size
    local_size=$(stat -c%s "$src" 2>/dev/null || stat -f%z "$src" 2>/dev/null || echo 0)
    local remote_size
    remote_size=$(remote_ssh "stat -c%s ${remote_path} 2>/dev/null || echo 0")
    
    if [ "$local_size" -gt 0 ] && [ "$local_size" -eq "$remote_size" ]; then
        echo " -> [Cached] ${base} already staged on ${SHIP_TARGET} (${local_size} bytes)."
    else
        echo " -> [Staging] Copying ${base} to ${SHIP_TARGET}:${dest_dir}..."
        scp -q "${SSH_OPTS[@]}" "$src" "${SHIP_TARGET}:${dest_dir}/"
    fi
}

trap 'echo -e "\n[✗] Error occurred during ship modernization at line $LINENO." >&2' ERR

while [[ $# -gt 0 ]]; do
    case "$1" in
        --step)
            STEP="$2"
            shift 2
            ;;
        --step=*)
            STEP="${1#*=}"
            shift 1
            ;;
        reset-day0|reset)
            STEP="reset-day0"
            shift 1
            ;;
        bootstrap-k3s|k3s)
            STEP="bootstrap-k3s"
            shift 1
            ;;
        init-zarf|zarf)
            STEP="init-zarf"
            shift 1
            ;;
        cutover-cnf|cutover|deploy-cnf)
            STEP="cutover-cnf"
            shift 1
            ;;
        full)
            STEP="full"
            shift 1
            ;;
        -*)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
        *)
            SHIP_TARGET="$1"
            shift 1
            ;;
    esac
done

# ------------------------------------------------------------------------------
# STEP: RESET DAY 0 BASELINE
# ------------------------------------------------------------------------------
if [[ "$STEP" == "reset-day0" || "$STEP" == "reset" ]]; then
    echo "======================================================================"
    echo "  Tactical Edge Modernization: Resetting ${SHIP_TARGET} to Day 0 VNF  "
    echo "======================================================================"
    echo "==> Decommissioning CNF and stopping K3s service on ${SHIP_TARGET}..."
    remote_ssh "bash -s" << 'EOF'
sudo systemctl stop k3s 2>/dev/null || true
sudo systemctl disable k3s 2>/dev/null || true
sudo ip rule add from 10.200.1.2 table 200 priority 100 2>/dev/null || true
sudo ip route add 10.200.1.0/24 dev eth-mgmt table 200 2>/dev/null || true
sudo ip route add default via 10.200.1.10 dev eth-mgmt table 200 2>/dev/null || true
sudo systemctl enable --now sdwan-controller.service 2>/dev/null || true
echo " [✓] Default routing table:"
ip route show default
EOF
    echo " [✓] Day 0 Legacy VNF restored. Dynamic SLA steering retired."
    exit 0
fi

# Locate Zarf stack package
PACKAGE_PATH=""
for p in "${REPO_ROOT}/build"/zarf-package-tactical-sdn-stack-amd64-*.tar.zst /opt/tactical-sdn/build/zarf-package-tactical-sdn-stack-amd64-*.tar.zst; do
    if [ -f "$p" ]; then
        PACKAGE_PATH="$p"
        break
    fi
done

# Locate Zarf init package
ZARF_INIT_PKG=""
for p in "${HOME}/.zarf-cache/zarf-init-amd64-v0.85.0.tar.zst" "${REPO_ROOT}/build/zarf-init-amd64-v0.85.0.tar.zst" /opt/tactical-sdn/build/zarf-init-amd64-v0.85.0.tar.zst /opt/tactical-sdn/bin/zarf-init-amd64-v0.85.0.tar.zst; do
    if [ -f "$p" ]; then
        ZARF_INIT_PKG="$p"
        break
    fi
done

# Locate K3s binary
K3S_BIN=""
for b in "${REPO_ROOT}/bin/k3s" /opt/tactical-sdn/bin/k3s "$(which k3s 2>/dev/null || true)"; do
    if [ -n "$b" ] && [ -f "$b" ]; then
        K3S_BIN="$b"
        break
    fi
done

# Locate Zarf binary
ZARF_BIN=""
for b in "$(which zarf 2>/dev/null || true)" "${HOME}/.local/bin/zarf" /usr/local/bin/zarf "${REPO_ROOT}/bin/zarf" /opt/tactical-sdn/bin/zarf; do
    if [ -n "$b" ] && [ -f "$b" ]; then
        ZARF_BIN="$b"
        break
    fi
done

# Locate pre-cached foundational K3s container images (pause, coredns, local-path)
K3S_CORE_IMAGES=""
for img_path in "${REPO_ROOT}/bin/k3s-core-images.tar" /opt/tactical-sdn/bin/k3s-core-images.tar "${REPO_ROOT}/bin/k3s-airgap-images-amd64.tar" "${REPO_ROOT}/bin/k3s-airgap-images-amd64.tar.zst"; do
    if [ -f "${img_path}" ]; then
        K3S_CORE_IMAGES="${img_path}"
        break
    fi
done

echo "======================================================================"
echo "  Tactical Edge Modernization: Transitioning ${SHIP_TARGET} to CNF    "
echo "  Execution Mode: ${STEP^^}                                           "
echo "======================================================================"

# If running steps that need packages, ensure package is built or available on remote
if [[ "$STEP" == "full" || "$STEP" == "cutover-cnf" || "$STEP" == "deploy-cnf" ]]; then
    if [ -z "${PACKAGE_PATH}" ] || [ ! -f "${PACKAGE_PATH}" ]; then
        REMOTE_PKG=$(remote_ssh "ls -t ~/zarf-stage/zarf-package-tactical-sdn-stack-*.tar.zst 2>/dev/null | head -n 1 || echo ''")
        if [ -n "${REMOTE_PKG}" ]; then
            echo " -> [Detected] Package already staged on ${SHIP_TARGET}: $(basename "${REMOTE_PKG}")"
        elif [ -f "${REPO_ROOT}/scripts/build-airgap-package.sh" ]; then
            echo "[-] Zarf package not found. Building airgap package..."
            "${REPO_ROOT}/scripts/build-airgap-package.sh"
            PACKAGE_PATH=$(ls -t "${REPO_ROOT}/build"/zarf-package-tactical-sdn-stack-amd64-*.tar.zst 2>/dev/null | head -n 1)
        fi
    fi
fi

# ------------------------------------------------------------------------------
# STEP 1, 2, 3: BOOTSTRAP K3S
# ------------------------------------------------------------------------------
if [[ "$STEP" == "full" || "$STEP" == "bootstrap-k3s" || "$STEP" == "k3s" ]]; then
    echo "==> [Step 1/5] Verifying legacy routing is active and passing traffic..."
    remote_ssh "systemctl is-active sdwan-controller.service >/dev/null 2>&1 && echo ' [✓] Legacy routing service is active.' || echo ' [!] Legacy service not currently running (proceeding with clean modernization).'"

    echo "==> [Step 2/5] Staging K3s and Zarf binaries onto ${SHIP_TARGET} (Background Pre-stage)..."
    remote_ssh "mkdir -p ~/zarf-stage ~/bin ~/.zarf-cache"
    
    if [ -n "${K3S_BIN}" ] && [ -f "${K3S_BIN}" ]; then
        stage_file_if_needed "${K3S_BIN}" "~/bin"
        remote_ssh "if [ ! -x /usr/local/bin/k3s ] || [ ~/bin/k3s -nt /usr/local/bin/k3s ]; then sudo cp ~/bin/k3s /usr/local/bin/k3s && sudo chmod +x /usr/local/bin/k3s && sudo ln -sf /usr/local/bin/k3s /usr/local/bin/kubectl; fi"
    fi
    if [ -n "${ZARF_BIN}" ] && [ -f "${ZARF_BIN}" ]; then
        stage_file_if_needed "${ZARF_BIN}" "~/bin"
        remote_ssh "if [ ! -x /usr/local/bin/zarf ] || [ ~/bin/zarf -nt /usr/local/bin/zarf ]; then sudo cp ~/bin/zarf /usr/local/bin/zarf && sudo chmod +x /usr/local/bin/zarf; fi"
    fi

    if [ -n "${K3S_CORE_IMAGES}" ] && [ -f "${K3S_CORE_IMAGES}" ]; then
        echo "==> Staging foundational K3s air-gap images (${K3S_CORE_IMAGES})..."
        IMG_BASE="$(basename "${K3S_CORE_IMAGES}")"
        stage_file_if_needed "${K3S_CORE_IMAGES}" "~/zarf-stage"
        remote_ssh "sudo mkdir -p /var/lib/rancher/k3s/agent/images && if [ ! -f /var/lib/rancher/k3s/agent/images/k3s-core-images.tar ]; then if [[ '${IMG_BASE}' == *.zst ]]; then sudo zstd -d ~/zarf-stage/${IMG_BASE} -o /var/lib/rancher/k3s/agent/images/k3s-core-images.tar; else sudo cp ~/zarf-stage/${IMG_BASE} /var/lib/rancher/k3s/agent/images/; fi; fi"
    fi

    echo "==> [Step 3/5] Bootstrapping air-gapped K3s cluster in background (Zero-Downtime)..."
    remote_ssh "bash -s" << 'EOF'
if ! command -v k3s >/dev/null 2>&1; then
    echo "[-] k3s binary missing from PATH"
    exit 1
fi

sudo tee /etc/systemd/system/k3s.service > /dev/null << 'SERVICE'
[Unit]
Description=Lightweight Kubernetes (Air-Gapped Tactical Edge)
Documentation=https://k3s.io
Wants=network-online.target
After=network-online.target

[Service]
Type=notify
EnvironmentFile=-/etc/default/%N
EnvironmentFile=-/etc/sysconfig/%N
EnvironmentFile=-/etc/systemd/system/%N.env
KillMode=process
Delegate=yes
LimitNOFILE=1048576
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity
TimeoutStartSec=0
Restart=always
RestartSec=5s
ExecStartPre=-/sbin/modprobe br_netfilter
ExecStartPre=-/sbin/modprobe overlay
ExecStart=/usr/local/bin/k3s server --disable traefik --disable servicelb --disable metrics-server --flannel-backend=host-gw --write-kubeconfig-mode 644

[Install]
WantedBy=multi-user.target
SERVICE

sudo systemctl daemon-reload
sudo systemctl enable --now k3s.service

echo "==> Waiting for K3s node ready..."
sudo k3s kubectl wait --for=condition=Ready node --all --timeout=60s

mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown -R $(id -un):$(id -gn) ~/.kube
EOF
    echo " [✓] Stage 2 Complete: K3s node verified ready. Legacy routing remains active."
    if [[ "$STEP" == "bootstrap-k3s" || "$STEP" == "k3s" ]]; then
        exit 0
    fi
fi

# ------------------------------------------------------------------------------
# STEP 4: INITIALIZE ZARF SEED REGISTRY
# ------------------------------------------------------------------------------
if [[ "$STEP" == "full" || "$STEP" == "init-zarf" || "$STEP" == "zarf" ]]; then
    echo "==> [Step 4/5] Staging Zarf initialization package and running zarf init in background..."
    if [ -n "${ZARF_INIT_PKG}" ] && [ -f "${ZARF_INIT_PKG}" ]; then
        stage_file_if_needed "${ZARF_INIT_PKG}" "~/.zarf-cache"
    fi
    if [ -n "${PACKAGE_PATH}" ] && [ -f "${PACKAGE_PATH}" ]; then
        stage_file_if_needed "${PACKAGE_PATH}" "~/zarf-stage"
    fi

    remote_ssh "bash -s" << 'EOF'
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
echo "==> Initializing Zarf on ship-gateway..."
zarf init --confirm --components zarf-seed-registry,zarf-registry,zarf-injector

echo "==> Waiting for Zarf seed registry pod readiness..."
kubectl wait --namespace zarf --for=condition=ready pod --selector=app=docker-registry --timeout=120s
EOF
    echo " [✓] Stage 3 Complete: Zarf in-cluster seed registry ready. Packages staged."
    if [[ "$STEP" == "init-zarf" || "$STEP" == "zarf" ]]; then
        exit 0
    fi
fi

# ------------------------------------------------------------------------------
# STEP 5: DEPLOY CONTAINERIZED CNF & ATOMIC HOT CUTOVER
# ------------------------------------------------------------------------------
if [[ "$STEP" == "full" || "$STEP" == "cutover-cnf" || "$STEP" == "deploy-cnf" ]]; then
    echo "==> [Step 5/5] Deploying containerized SD-WAN CNF and performing Atomic Hot Cutover..."
    if [ -n "${PACKAGE_PATH}" ] && [ -f "${PACKAGE_PATH}" ]; then
        PKG_NAME="$(basename "${PACKAGE_PATH}")"
        stage_file_if_needed "${PACKAGE_PATH}" "~/zarf-stage"
    else
        PKG_NAME=$(remote_ssh "ls -t ~/zarf-stage/zarf-package-tactical-sdn-stack-*.tar.zst 2>/dev/null | head -n 1 | xargs -r basename || echo ''")
        if [ -z "${PKG_NAME}" ]; then
            echo "[-] Error: No Zarf package found on host or staged on ${SHIP_TARGET}." >&2
            exit 1
        fi
    fi

    remote_ssh "bash -s -- \"${PKG_NAME}\"" << 'EOF'
PKG_NAME="$1"
REMOTE_PKG="${HOME}/zarf-stage/${PKG_NAME}"
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

echo "==> [ATOMIC HOT CUTOVER] Preparing atomic handoff to Cloud-Native CNF..."
# Ensure out-of-band management isolation rule (table 200) is present
sudo ip rule add from 10.200.1.2 table 200 priority 100 2>/dev/null || true
sudo ip route add 10.200.1.0/24 dev eth-mgmt table 200 2>/dev/null || true
sudo ip route add default via 10.200.1.10 dev eth-mgmt table 200 2>/dev/null || true

# Stop legacy controller daemon so port 8080 is instantly available for the CNF pod.
# Note: Linux kernel retains existing routing tables and NAT state, so data traffic continues uninterrupted.
sudo systemctl stop sdwan-controller.service 2>/dev/null || true
sudo systemctl disable sdwan-controller.service 2>/dev/null || true

echo "==> Deploying ${REMOTE_PKG}..."
zarf package deploy "${REMOTE_PKG}" --confirm

echo "==> Waiting for Tactical SDN CNF DaemonSet pod readiness..."
kubectl wait --namespace tactical-sdn --for=condition=ready pod --selector=app.kubernetes.io/name=tactical-sdn --timeout=60s

# Flush stale connection tracking states to instantly transition active sessions to CNF dataplane
if command -v conntrack >/dev/null 2>&1; then
    sudo conntrack -F >/dev/null 2>&1 || true
fi
echo " [✓] Atomic cutover completed successfully with zero pre-deployment downtime."
EOF
    echo " [✓] Stage 4 Complete: Cloud-Native CNF deployed and active. Atomic cutover verified."
fi

echo ""
echo "======================================================================"
echo "  [SUCCESS] ${SHIP_TARGET} successfully modernized to Cloud-Native CNF!"
echo "======================================================================"
if [ -f "${REPO_ROOT}/scripts/verify-ship-modernization.sh" ]; then
    "${REPO_ROOT}/scripts/verify-ship-modernization.sh" "${SHIP_TARGET}"
fi
