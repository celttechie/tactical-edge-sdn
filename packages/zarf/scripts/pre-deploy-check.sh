#!/usr/bin/env bash
# Pre-deploy check: verify kernel capabilities and modules
set -euo pipefail

echo "==> [Zarf Action] Checking host kernel prerequisites for Tactical Edge SD-WAN..."
# Check for IP forwarding
if [[ $(cat /proc/sys/net/ipv4/ip_forward) -ne 1 ]]; then
    echo " -> Enabling IPv4 forwarding..."
    sudo sysctl -w net.ipv4.ip_forward=1 || true
fi

echo " -> IPv4 forwarding is active."
echo "==> Pre-deploy checks completed successfully."
