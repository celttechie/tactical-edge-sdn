#!/usr/bin/env bash
# ==============================================================================
# Sandbox Hypervisor Libvirt Tunnel Helper
# Forwards local port 16509 to the nested Libvirt socket on sandbox-hypervisor-node
# ==============================================================================

set -euo pipefail

CTRL_SOCK="/tmp/sandbox-ssh-ctrl.sock"
LOCAL_PORT="${LOCAL_PORT:-16509}"
REMOTE_HOST="sandbox-hypervisor-node"
REMOTE_SOCK="/var/run/libvirt/libvirt-sock"

is_running() {
    ssh -S "$CTRL_SOCK" -O check "$REMOTE_HOST" >/dev/null 2>&1
}

start_tunnel() {
    if is_running; then
        echo "==> Sandbox Libvirt tunnel is already active on port $LOCAL_PORT."
        return 0
    fi
    echo "==> Starting Libvirt SSH tunnel to $REMOTE_HOST (127.0.0.1:$LOCAL_PORT -> $REMOTE_SOCK)..."
    rm -f "$CTRL_SOCK"
    ssh -f -N -M -S "$CTRL_SOCK" -L "${LOCAL_PORT}:${REMOTE_SOCK}" "$REMOTE_HOST"
    sleep 1
    if is_running; then
        echo "==> Tunnel established successfully."
    else
        echo "==> ERROR: Failed to establish Libvirt tunnel." >&2
        return 1
    fi
}

stop_tunnel() {
    if is_running; then
        echo "==> Stopping Sandbox Libvirt tunnel..."
        ssh -S "$CTRL_SOCK" -O exit "$REMOTE_HOST" >/dev/null 2>&1 || true
        rm -f "$CTRL_SOCK"
        echo "==> Tunnel stopped."
    else
        echo "==> Sandbox Libvirt tunnel is not running."
    fi
}

status_tunnel() {
    if is_running; then
        echo "==> Sandbox Libvirt tunnel: ACTIVE (127.0.0.1:$LOCAL_PORT)"
        virsh -c "qemu+tcp://127.0.0.1:$LOCAL_PORT/system" list --all
    else
        echo "==> Sandbox Libvirt tunnel: INACTIVE"
    fi
}

case "${1:-}" in
    start)
        start_tunnel
        ;;
    stop)
        stop_tunnel
        ;;
    status)
        status_tunnel
        ;;
    restart)
        stop_tunnel
        start_tunnel
        ;;
    *)
        echo "Usage: $0 [start | stop | status | restart]"
        exit 1
        ;;
esac
