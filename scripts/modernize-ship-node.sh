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

# Locate pre-cached foundational K3s container images (pause, coredns, local-path)
K3S_CORE_IMAGES=""
for img_path in "${REPO_ROOT}/bin/k3s-core-images.tar" "${REPO_ROOT}/bin/k3s-airgap-images-amd64.tar" "${REPO_ROOT}/bin/k3s-airgap-images-amd64.tar.zst"; do
    if [ -f "${img_path}" ]; then
        K3S_CORE_IMAGES="${img_path}"
        break
    fi
done

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
if [ -n "${K3S_CORE_IMAGES}" ] && [ -f "${K3S_CORE_IMAGES}" ]; then
    echo "==> Staging foundational K3s air-gap images (${K3S_CORE_IMAGES})..."
    IMG_BASE="$(basename "${K3S_CORE_IMAGES}")"
    scp -q "${K3S_CORE_IMAGES}" "${SHIP_TARGET}:~/zarf-stage/${IMG_BASE}"
    ssh "${SHIP_TARGET}" "sudo mkdir -p /var/lib/rancher/k3s/agent/images && if [[ '${IMG_BASE}' == *.zst ]]; then sudo zstd -d ~/zarf-stage/${IMG_BASE} -o /var/lib/rancher/k3s/agent/images/k3s-core-images.tar; else sudo cp ~/zarf-stage/${IMG_BASE} /var/lib/rancher/k3s/agent/images/; fi"
fi
ssh "${SHIP_TARGET}" "sudo cp ~/bin/k3s /usr/local/bin/k3s && sudo cp ~/bin/zarf /usr/local/bin/zarf && sudo chmod +x /usr/local/bin/k3s /usr/local/bin/zarf && sudo ln -sf /usr/local/bin/k3s /usr/local/bin/kubectl"

echo "==> [Step 3/5] Bootstrapping air-gapped K3s cluster on ${SHIP_TARGET}..."
ssh "${SHIP_TARGET}" "bash -s" << 'EOF'
if ! command -v k3s >/dev/null 2>&1; then
    echo "[-] k3s binary missing from PATH"
    exit 1
fi

# Configure K3s service unit with host networking and no traefik/servicelb/metrics-server to minimize SWaP
# NOTE: local-storage is preserved to satisfy Zarf registry PVC requirements
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

echo "==> [Step 4/5] Staging Zarf initialization package and running zarf init..."
scp -q "${ZARF_INIT_PKG}" "${SHIP_TARGET}:~/.zarf-cache/zarf-init-amd64-v0.85.0.tar.zst"
scp -q "${PACKAGE_PATH}" "${SHIP_TARGET}:~/zarf-stage/"

ssh "${SHIP_TARGET}" "bash -s" << 'EOF'
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
echo "==> Initializing Zarf on ship-gateway..."
zarf init --confirm --components zarf-seed-registry,zarf-registry,zarf-injector

echo "==> Waiting for Zarf seed registry pod readiness..."
kubectl wait --namespace zarf --for=condition=ready pod --selector=app=docker-registry --timeout=120s
EOF

echo "==> [Step 5/5] Deploying containerized SD-WAN CNF via Zarf on ${SHIP_TARGET}..."
REMOTE_PKG="~/zarf-stage/$(basename "${PACKAGE_PATH}")"
ssh "${SHIP_TARGET}" "bash -s" << EOF
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
echo "==> Deploying ${REMOTE_PKG}..."
zarf package deploy ${REMOTE_PKG} --confirm

echo "==> Waiting for Tactical SDN CNF DaemonSet pod readiness..."
kubectl wait --namespace tactical-sdn --for=condition=ready pod --selector=app.kubernetes.io/name=tactical-sdn --timeout=60s
EOF

echo ""
echo "======================================================================"
echo "  [SUCCESS] ${SHIP_TARGET} successfully modernized to Cloud-Native CNF!"
echo "======================================================================"
"${REPO_ROOT}/scripts/verify-ship-modernization.sh" "${SHIP_TARGET}"
