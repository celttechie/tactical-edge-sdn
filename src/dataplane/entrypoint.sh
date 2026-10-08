#!/usr/bin/env bash
set -euo pipefail

echo "=========================================================="
echo "Starting Tactical Edge SDN CNF Dataplane & Controller"
echo "=========================================================="

# 1. Enable IP Forwarding (host kernel default; non-fatal in unprivileged containers)
sysctl -w net.ipv4.ip_forward=1 2>/dev/null || true
sysctl -w net.ipv4.conf.all.rp_filter=0 2>/dev/null || true
sysctl -w net.ipv4.conf.default.rp_filter=0 2>/dev/null || true

# 2. Ensure writable runtime directories exist on ephemeral emptyDir mounts
mkdir -p /run/frr /var/run/frr /var/log/frr /tmp
chown -R frr:frr /run/frr /var/run/frr /var/log/frr 2>/dev/null || true
chmod 755 /run/frr /var/run/frr 2>/dev/null || true

# 3. Start FRR daemons if installed
if command -v /usr/lib/frr/frrinit.sh >/dev/null 2>&1; then
    echo "==> Initializing FRRouting daemons (zebra, bgpd, bfdd)..."
    /usr/lib/frr/frrinit.sh start || true
elif command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files | grep -q frr; then
    systemctl start frr || true
fi

# 4. Configure baseline NAT/MASQUERADE for shipboard enclaves
echo "==> Configuring IPTables NAT across bearer interfaces..."
iptables -t nat -A POSTROUTING -s 10.10.0.0/16 -o eth-pleops -j MASQUERADE 2>/dev/null || true
iptables -t nat -A POSTROUTING -s 10.10.0.0/16 -o eth-milsat -j MASQUERADE 2>/dev/null || true
iptables -t nat -A POSTROUTING -s 10.10.0.0/16 -o eth-losrf -j MASQUERADE 2>/dev/null || true
iptables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
iptables -A FORWARD -s 10.10.0.0/16 -j ACCEPT 2>/dev/null || true

# 5. Launch the SD-WAN Policy Controller Daemon
echo "==> Launching SD-WAN Policy Controller Daemon..."
exec python3 -m src.controller.main "$@"
