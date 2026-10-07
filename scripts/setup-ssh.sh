#!/usr/bin/env bash
# ==============================================================================
# Tactical Edge SDN - Automated Lab SSH Onboarding & Setup Script
# Configures dedicated SSH keypairs, updates ~/.ssh/config with StrictHostKeyChecking
# accept-new, seeds known_hosts, and prepares terraform.tfvars.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Color codes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

CURRENT_USER="$(id -un)"
DEFAULT_KEY="$HOME/.ssh/id_sandbox_hypervisor_ed25519"
DEFAULT_HYPERVISOR="sandbox-hypervisor-node"

VM_USER="${VM_USER:-$CURRENT_USER}"
SSH_KEY="${SSH_KEY:-$DEFAULT_KEY}"
HYPERVISOR_HOST="${HYPERVISOR_HOST:-$DEFAULT_HYPERVISOR}"
NON_INTERACTIVE=false

for arg in "$@"; do
    case "$arg" in
        --non-interactive|-y)
            NON_INTERACTIVE=true
            ;;
        --user=*)
            VM_USER="${arg#*=}"
            ;;
        --key=*)
            SSH_KEY="${arg#*=}"
            ;;
        --hypervisor=*)
            HYPERVISOR_HOST="${arg#*=}"
            ;;
        --help|-h)
            echo "Usage: $0 [--non-interactive] [--user=<username>] [--key=<ssh_key_path>] [--hypervisor=<host>]"
            exit 0
            ;;
    esac
done

echo -e "${BLUE}======================================================================${NC}"
echo -e "${BLUE}  Tactical Edge SDN - Lab SSH Onboarding & Configuration Setup       ${NC}"
echo -e "${BLUE}======================================================================${NC}"

# 1. Prompt if interactive
if [ "$NON_INTERACTIVE" = false ]; then
    read -r -p "Enter administrative username for VMs [$VM_USER]: " input_user
    VM_USER="${input_user:-$VM_USER}"

    read -r -p "Enter SSH private key path [$SSH_KEY]: " input_key
    SSH_KEY="${input_key:-$SSH_KEY}"

    read -r -p "Enter L2 Hypervisor SSH Host alias [$HYPERVISOR_HOST]: " input_hyp
    HYPERVISOR_HOST="${input_hyp:-$HYPERVISOR_HOST}"
fi

SSH_KEY="${SSH_KEY/#\~/$HOME}"
SSH_PUB_KEY="${SSH_KEY}.pub"
SSH_DIR="$HOME/.ssh"
SSH_CONFIG="$SSH_DIR/config"
KNOWN_HOSTS="$SSH_DIR/known_hosts"

mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

# 2. Ensure SSH Keypair exists
if [ ! -f "$SSH_KEY" ]; then
    echo -e "\n==> Generating dedicated Ed25519 SSH keypair: ${SSH_KEY}..."
    ssh-keygen -t ed25519 -f "$SSH_KEY" -C "tactical-sdn-lab-${VM_USER}" -N ""
    chmod 600 "$SSH_KEY"
    chmod 644 "$SSH_PUB_KEY"
    echo -e "${GREEN}==> SSH keypair generated successfully.${NC}"
else
    echo -e "==> Using existing SSH keypair: ${SSH_KEY}"
fi

# 3. Ensure ~/.ssh/config exists
touch "$SSH_CONFIG"
chmod 600 "$SSH_CONFIG"

# 4. Inject Lab Host Aliases into ~/.ssh/config
echo -e "\n==> Configuring SSH host entries in ${SSH_CONFIG}..."

cat << 'EOF' > /tmp/tactical_sdn_ssh_block.tmp
# ==============================================================================
# Tactical Edge SDN - Ephemeral Lab VM Topologies
# ==============================================================================
EOF

for vm in "ship-gateway 10.200.1.2 ${HYPERVISOR_HOST}" "shore-gateway 10.200.1.10 ${HYPERVISOR_HOST}" "enclave-client 10.10.1.10 ship-gateway"; do
    alias_name=$(echo "$vm" | awk '{print $1}')
    ip_addr=$(echo "$vm" | awk '{print $2}')
    proxy_target=$(echo "$vm" | awk '{print $3}')
    
    extra_alias=""
    if [ "$alias_name" = "ship-gateway" ]; then
        extra_alias=" legacy-router"
    fi

    cat << EOF >> /tmp/tactical_sdn_ssh_block.tmp
Host ${alias_name}${extra_alias} ${ip_addr}
    HostName ${ip_addr}
    User ${VM_USER}
    ProxyJump ${proxy_target}
    IdentityFile ${SSH_KEY}
    UserKnownHostsFile ~/.ssh/known_hosts_tactical_lab
    StrictHostKeyChecking accept-new
    IdentitiesOnly yes

EOF
done

# If Host legacy-router or ship-gateway already exists in ~/.ssh/config, update or skip
if grep -qE "Host (legacy-router|ship-gateway)" "$SSH_CONFIG"; then
    echo -e "${YELLOW}==> Existing tactical entries present in ${SSH_CONFIG}. Updating entries...${NC}"
    # Remove existing tactical block if present
    python3 -c "
import re
with open('$SSH_CONFIG', 'r') as f:
    content = f.read()
# Replace legacy-router / ship-gateway, shore-gateway, enclave-client blocks
pattern = r'# ===+.*?Tactical Edge SDN.*?enclave-client.*?\n\n'
new_content = re.sub(pattern, '', content, flags=re.DOTALL)
with open('$SSH_CONFIG', 'w') as f:
    f.write(new_content)
" 2>/dev/null || true
fi

cat /tmp/tactical_sdn_ssh_block.tmp >> "$SSH_CONFIG"
rm -f /tmp/tactical_sdn_ssh_block.tmp
echo -e "${GREEN}==> Host aliases added to ${SSH_CONFIG} with StrictHostKeyChecking accept-new.${NC}"

# 5. Populate terraform.tfvars if missing
TFVARS_FILE="$PROJECT_ROOT/infra/tofu/terraform.tfvars"
if [ ! -f "$TFVARS_FILE" ]; then
    echo -e "\n==> Generating initial infra/tofu/terraform.tfvars..."
    cat << EOF > "$TFVARS_FILE"
# Auto-generated by scripts/setup-ssh.sh
admin_username       = "${VM_USER}"
ssh_public_key_path  = "${SSH_PUB_KEY}"
ssh_private_key_path = "${SSH_KEY}"
hypervisor_ssh_host  = "${HYPERVISOR_HOST}"
storage_pool         = "default"
libvirt_uri          = "qemu+tcp://127.0.0.1:16509/system"
EOF
    echo -e "${GREEN}==> Created ${TFVARS_FILE}.${NC}"
else
    echo -e "==> ${TFVARS_FILE} already exists. Leaving unchanged."
fi

# 6. Test Hypervisor Connection
echo -e "\n==> Verifying connection to L2 hypervisor (${HYPERVISOR_HOST})..."
if ssh -o BatchMode=yes -o ConnectTimeout=5 "$HYPERVISOR_HOST" "hostname" >/dev/null 2>&1; then
    hyp_name=$(ssh -o BatchMode=yes -o ConnectTimeout=5 "$HYPERVISOR_HOST" "hostname")
    echo -e "${GREEN}==> [PASS] L2 Hypervisor reachable: ${hyp_name}${NC}"
else
    echo -e "${YELLOW}==> [WARN] L2 Hypervisor '${HYPERVISOR_HOST}' not reachable passwordlessly.${NC}"
    echo -e "    Ensure '${HYPERVISOR_HOST}' is configured in ${SSH_CONFIG} and keys are copied."
fi

echo -e "\n${BLUE}======================================================================${NC}"
echo -e "${GREEN}  Lab SSH Configuration Complete!${NC}"
echo -e "${BLUE}  You can now connect to lab VMs directly with host key verification:${NC}"
echo -e "    ssh ship-gateway"
echo -e "    ssh shore-gateway"
echo -e "    ssh enclave-client"
echo -e "${BLUE}======================================================================${NC}\n"
