#!/usr/bin/env bash
# ==============================================================================
# Tactical Operations HUD Persistent Tunnel Daemon
# Forwards port 8080 on all host interfaces (0.0.0.0:8080) to shore-gateway
# ==============================================================================

set -euo pipefail

PID_FILE="/tmp/tactical-dashboard-tunnel.pid"
LOCAL_PORT="${LOCAL_PORT:-8080}"
SHORE_HOST="10.200.1.10"
HYPERVISOR_HOST="sandbox-hypervisor-node"

LAN_IP=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{print $7}' || hostname -I | awk '{print $1}')
LAN_IP="${LAN_IP:-127.0.0.1}"
TAILSCALE_IP=$(ip -4 addr show tailscale0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || echo "")

SERVICE_NAME="tactical-dashboard-proxy.service"
USER_SYSTEMD_DIR="${HOME}/.config/systemd/user"
SERVICE_PATH="${USER_SYSTEMD_DIR}/${SERVICE_NAME}"

has_systemd_service() {
    [[ -f "$SERVICE_PATH" ]]
}

is_systemd_active() {
    systemctl --user is-active --quiet "$SERVICE_NAME" 2>/dev/null
}

is_running() {
    if is_systemd_active; then
        return 0
    fi
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

print_urls() {
    echo "==> Access on Localhost at: http://localhost:$LOCAL_PORT"
    echo "==> Access on LAN at:       http://${LAN_IP}:$LOCAL_PORT"
    if [[ -n "$TAILSCALE_IP" ]]; then
        echo "==> Access on Tailscale at: http://${TAILSCALE_IP}:$LOCAL_PORT"
    fi
}

start_tunnel() {
    if is_running; then
        echo "==> Tactical Operations HUD tunnel is already active."
        print_urls
        return 0
    fi

    if has_systemd_service; then
        echo "==> Starting via systemd user unit (${SERVICE_NAME})..."
        systemctl --user start "$SERVICE_NAME"
        sleep 1.5
        if is_running; then
            echo "==> Tactical Operations HUD tunnel started via systemd."
            print_urls
            return 0
        fi
    fi

    echo "==> Starting persistent Tactical HUD tunnel (0.0.0.0:$LOCAL_PORT -> $SHORE_HOST:8080)..."
    rm -f "$PID_FILE"
    nohup ssh -N \
        -o "StrictHostKeyChecking=no" \
        -o "UserKnownHostsFile=/dev/null" \
        -o "ServerAliveInterval=15" \
        -o "ServerAliveCountMax=4" \
        -o "ExitOnForwardFailure=yes" \
        -L "0.0.0.0:${LOCAL_PORT}:${SHORE_HOST}:8080" \
        "$HYPERVISOR_HOST" >/dev/null 2>&1 &
    
    local new_pid=$!
    echo "$new_pid" > "$PID_FILE"
    sleep 1.5

    if is_running; then
        echo "==> Tunnel established successfully (PID: $new_pid)."
        print_urls
    else
        echo "==> ERROR: Failed to establish Tactical HUD tunnel." >&2
        return 1
    fi
}

stop_tunnel() {
    if is_systemd_active; then
        echo "==> Stopping systemd user unit (${SERVICE_NAME})..."
        systemctl --user stop "$SERVICE_NAME" 2>/dev/null || true
    fi
    if [[ -f "$PID_FILE" ]]; then
        local pid
        pid=$(cat "$PID_FILE")
        kill "$pid" 2>/dev/null || true
        rm -f "$PID_FILE"
    fi
    pkill -f "ssh -N.*:${LOCAL_PORT}:" 2>/dev/null || true
    echo "==> Tactical HUD tunnel stopped."
}

status_tunnel() {
    if is_running; then
        local mode="BACKGROUND PROCESS"
        if is_systemd_active; then
            mode="SYSTEMD USER SERVICE"
        fi
        echo "==> Tactical HUD tunnel: ACTIVE [${mode}] (0.0.0.0:$LOCAL_PORT -> $SHORE_HOST:8080)"
        print_urls
    else
        echo "==> Tactical HUD tunnel: INACTIVE"
    fi
}

install_service() {
    echo "==> Installing systemd user unit: ${SERVICE_PATH}..."
    mkdir -p "$USER_SYSTEMD_DIR"
    cat << EOF > "$SERVICE_PATH"
[Unit]
Description=Tactical Edge SD-WAN Dashboard Host Proxy
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/ssh -N -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ServerAliveInterval=15 -o ServerAliveCountMax=3 -o ExitOnForwardFailure=yes -L 0.0.0.0:${LOCAL_PORT}:${SHORE_HOST}:8080 ${HYPERVISOR_HOST}
Restart=always
RestartSec=3

[Install]
WantedBy=default.target
EOF
    systemctl --user daemon-reload
    systemctl --user enable --now "$SERVICE_NAME"
    echo "==> ${SERVICE_NAME} installed and enabled."
    print_urls
}

uninstall_service() {
    echo "==> Removing systemd user unit: ${SERVICE_PATH}..."
    systemctl --user stop "$SERVICE_NAME" 2>/dev/null || true
    systemctl --user disable "$SERVICE_NAME" 2>/dev/null || true
    rm -f "$SERVICE_PATH"
    systemctl --user daemon-reload
    echo "==> ${SERVICE_NAME} uninstalled."
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
    install-service)
        install_service
        ;;
    uninstall-service)
        uninstall_service
        ;;
    *)
        echo "Usage: $0 [start | stop | status | restart | install-service | uninstall-service]"
        exit 1
        ;;
esac
