#!/usr/bin/env bash
# ==============================================================================
# modernize-ship-node.sh
# Upgrades the shipboard gateway node from legacy systemd VNF to cloud-native
# K3s orchestrator and deploys the containerized SD-WAN CNF via Zarf.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SHIP_TARGET="${1:-ship-gateway}"
PACKAGE_PATH=$(ls -t "${REPO_ROOT}/build"/zarf-package-tactical-sdn-stack-amd64-*.tar.zst 2>/dev/null | head -n 1 || true)
ZARF_INIT_PKG="${HOME}/.zarf-cache/zarf-init-amd64-v0.85.0.tar.zst"
K3S_BIN="${REPO_ROOT}/bin/k3s"
ZARF_BIN="$(which zarf || echo "${HOME}/.local/bin/zarf")"

echo "======================================================================"
echo "  Tactical Edge Modernization: Transitioning ${SHIP_TARGET} to CNF    "
echo "======================================================================"

if [ -z "${PACKAGE_PATH}" ] || [ ! -f "${PACKAGE_PATH}" ]; then
    echo "[-] Error: Zarf package not found in ${REPO_ROOT}/build/."
    echo "    Running build-airgap-package.sh first..."
    "${REPO_ROOT}/scripts/build-airgap-package.sh"
    PACKAGE_PATH=$(ls -t "${REPO_ROOT}/build"/zarf-package-tactical-sdn-stack-amd64-*.tar.zst 2>/dev/null | head -n 1)
fi

echo "==> [Step 1/5] Stopping legacy systemd routing daemons on ${SHIP_TARGET}..."
ssh "${SHIP_TARGET}" "sudo systemctl stop sdwan-controller.service || true; sudo systemctl disable sdwan-controller.service || true"

echo "==> [Step 2/5] Staging K3s and Zarf binaries onto ${SHIP_TARGET}..."
ssh "${SHIP_TARGET}" "mkdir -p ~/zarf-stage ~/bin ~/.zarf-cache"
scp -q "${K3S_BIN}" "${SHIP_TARGET}:~/bin/k3s"
scp -q "${ZARF_BIN}" "${SHIP_TARGET}:~/bin/zarf"
ssh "${SHIP_TARGET}" "sudo cp ~/bin/k3s /usr/local/bin/k3s && sudo cp ~/bin/zarf /usr/local/bin/zarf && sudo chmod +x /usr/local/bin/k3s /usr/local/bin/zarf"

echo "==> [Step 3/5] Bootstrapping air-gapped K3s cluster on ${SHIP_TARGET}..."
ssh "${SHIP_TARGET}" "bash -s" << 'EOF'
if ! command -v k3s >/dev/null 2>&1; then
    echo "[-] k3s binary missing from PATH"
    exit 1
fi

# Configure K3s service unit with host networking and no traefik/servicelb to minimize SWaP
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
ExecStart=/usr/local/bin/k3s server --disable traefik --disable servicelb --disable local-storage --flannel-backend=host-gw --write-kubeconfig-mode 644

[Install]
WantedBy=multi-user.target
SERVICE

sudo systemctl daemon-reload
sudo systemctl enable --now k3s.service

echo "==> Waiting for K3s node ready..."
for i in {1..30}; do
    if sudo k3s kubectl get nodes 2>/dev/null | grep -q " Ready"; then
        echo "==> K3s node is Ready!"
        break
    fi
    sleep 2
done
EOF

echo "==> [Step 4/5] Staging Zarf initialization package and running zarf init..."
scp -q "${ZARF_INIT_PKG}" "${SHIP_TARGET}:~/.zarf-cache/zarf-init-amd64-v0.85.0.tar.zst"
scp -q "${PACKAGE_PATH}" "${SHIP_TARGET}:~/zarf-stage/"

ssh "${SHIP_TARGET}" "bash -s" << 'EOF'
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
echo "==> Initializing Zarf on ship-gateway..."
zarf init --confirm --components zarf-seed-registry,zarf-registry,zarf-injector
EOF

echo "==> [Step 5/5] Deploying containerized SD-WAN CNF via Zarf on ${SHIP_TARGET}..."
REMOTE_PKG="~/zarf-stage/$(basename "${PACKAGE_PATH}")"
ssh "${SHIP_TARGET}" "bash -s" << EOF
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
echo "==> Deploying ${REMOTE_PKG}..."
zarf package deploy ${REMOTE_PKG} --confirm
EOF

echo ""
echo "======================================================================"
echo "  [SUCCESS] ${SHIP_TARGET} successfully modernized to Cloud-Native CNF!"
echo "======================================================================"
ssh "${SHIP_TARGET}" "sudo k3s kubectl get pods -n tactical-sdn -o wide"
