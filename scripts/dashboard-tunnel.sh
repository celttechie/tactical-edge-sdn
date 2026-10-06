#!/usr/bin/env bash
# ==============================================================================
# Tactical Operations HUD Persistent Tunnel Daemon
# Forwards port 8080 on all host interfaces (0.0.0.0:8080) to legacy-router
# ==============================================================================

set -euo pipefail

PID_FILE="/tmp/tactical-dashboard-tunnel.pid"
LOCAL_PORT="${LOCAL_PORT:-8080}"
ROUTER_HOST="10.200.1.2"
HYPERVISOR_HOST="sandbox-hypervisor-node"

LAN_IP=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{print $7}' || hostname -I | awk '{print $1}')
LAN_IP="${LAN_IP:-127.0.0.1}"

is_running() {
    if [[ -f "$PID_FILE" ]]; then
        local pid
        pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            return 0
        fi
    fi
    # Also check if port 8080 is actively listening
    if ss -tulpn | grep -q ":${LOCAL_PORT} "; then
        return 0
    fi
    return 1
}

start_tunnel() {
    if is_running; then
        echo "==> Tactical Operations HUD tunnel is already active."
        echo "==> Access on LAN at: http://${LAN_IP}:$LOCAL_PORT"
        echo "==> Access on Tailscale at: http://100.107.173.30:$LOCAL_PORT"
        echo "==> Access on Localhost at: http://localhost:$LOCAL_PORT"
        return 0
    fi
    echo "==> Starting persistent Tactical HUD tunnel (0.0.0.0:$LOCAL_PORT -> $ROUTER_HOST:8080)..."
    rm -f "$PID_FILE"
    nohup ssh -N \
        -o "StrictHostKeyChecking=no" \
        -o "UserKnownHostsFile=/dev/null" \
        -o "ServerAliveInterval=15" \
        -o "ServerAliveCountMax=4" \
        -o "ExitOnForwardFailure=yes" \
        -L "0.0.0.0:${LOCAL_PORT}:${ROUTER_HOST}:8080" \
        "$HYPERVISOR_HOST" >/dev/null 2>&1 &
    
    local new_pid=$!
    echo "$new_pid" > "$PID_FILE"
    sleep 1.5

    if is_running; then
        echo "==> Tunnel established successfully (PID: $new_pid)."
        echo "==> Access on LAN at: http://${LAN_IP}:$LOCAL_PORT"
        echo "==> Access on Tailscale at: http://100.107.173.30:$LOCAL_PORT"
        echo "==> Access on Localhost at: http://localhost:$LOCAL_PORT"
    else
        echo "==> ERROR: Failed to establish Tactical HUD tunnel." >&2
        return 1
    fi
}

stop_tunnel() {
    if [[ -f "$PID_FILE" ]]; then
        local pid
        pid=$(cat "$PID_FILE")
        kill "$pid" 2>/dev/null || true
        rm -f "$PID_FILE"
    fi
    pkill -f "ssh -N.*0.0.0.0:${LOCAL_PORT}:${ROUTER_HOST}:8080" 2>/dev/null || true
    echo "==> Tactical HUD tunnel stopped."
}

status_tunnel() {
    if is_running; then
        echo "==> Tactical HUD tunnel: ACTIVE (0.0.0.0:$LOCAL_PORT -> $ROUTER_HOST:8080)"
        echo "==> LAN URL: http://${LAN_IP}:$LOCAL_PORT"
        echo "==> Tailscale URL: http://100.107.173.30:$LOCAL_PORT"
        echo "==> Localhost URL: http://localhost:$LOCAL_PORT"
    else
        echo "==> Tactical HUD tunnel: INACTIVE"
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
