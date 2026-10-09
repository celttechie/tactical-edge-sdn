#!/usr/bin/env bash
# ==============================================================================
# Tactical Dashboard Shore Gateway Tunnel Helper
# Forwards local port 8080 to http://127.0.0.1:8080 on shore-gateway
# where the Operations HUD and Telemetry Orchestrator runs natively.
# ==============================================================================

set -euo pipefail

PID_FILE="/tmp/shore-dashboard-tunnel.pid"
LOCAL_PORT="${LOCAL_PORT:-8080}"
REMOTE_HOST="${SHORE_GATEWAY_HOST:-shore-gateway}"
REMOTE_PORT="${REMOTE_PORT:-8080}"

is_running() {
    if [[ -f "$PID_FILE" ]]; then
        local pid
        pid=$(cat "$PID_FILE" 2>/dev/null || echo "")
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            return 0
        fi
    fi
    # Also check if any SSH tunnel process matches
    pgrep -f "ssh.*${LOCAL_PORT}:127.0.0.1:${REMOTE_PORT}.*${REMOTE_HOST}" >/dev/null 2>&1
}

start_tunnel() {
    if is_running; then
        echo "==> Shore Dashboard tunnel is already active on port $LOCAL_PORT."
        echo "==> Access Dashboard at: http://localhost:$LOCAL_PORT/"
        return 0
    fi

    # Check if local port is occupied by another process
    if lsof -Pi :"$LOCAL_PORT" -sTCP:LISTEN -t >/dev/null 2>&1; then
        echo "==> ERROR: Local port $LOCAL_PORT is already in use by another process." >&2
        echo "==> Run 'lsof -i :$LOCAL_PORT' to inspect." >&2
        return 1
    fi

    echo "==> Starting SSH port-forward tunnel to $REMOTE_HOST (127.0.0.1:$LOCAL_PORT -> 127.0.0.1:$REMOTE_PORT)..."
    rm -f "$PID_FILE"

    ssh -f \
        -o BatchMode=yes \
        -o StrictHostKeyChecking=accept-new \
        -o ServerAliveInterval=15 \
        -o ServerAliveCountMax=4 \
        -o ExitOnForwardFailure=yes \
        -L "${LOCAL_PORT}:127.0.0.1:${REMOTE_PORT}" \
        "$REMOTE_HOST" "sleep infinity"

    # Capture PID
    sleep 1
    local tunnel_pid
    tunnel_pid=$(pgrep -f "ssh.*${LOCAL_PORT}:127.0.0.1:${REMOTE_PORT}.*${REMOTE_HOST}" | head -n 1 || echo "")
    if [[ -n "$tunnel_pid" ]]; then
        echo "$tunnel_pid" > "$PID_FILE"
    fi

    for i in {1..20}; do
        if is_running && curl -s -o /dev/null -w "%{http_code}" "http://localhost:$LOCAL_PORT/health" 2>/dev/null | grep -q "200"; then
            echo "==> Dashboard tunnel established successfully."
            echo "==> Operations HUD is live at: http://localhost:$LOCAL_PORT/"
            return 0
        fi
        sleep 0.5
    done

    echo "==> ERROR: Failed to establish Dashboard tunnel to $REMOTE_HOST." >&2
    return 1
}

stop_tunnel() {
    local stopped=false
    if [[ -f "$PID_FILE" ]]; then
        local pid
        pid=$(cat "$PID_FILE" 2>/dev/null || echo "")
        if [[ -n "$pid" ]]; then
            kill "$pid" 2>/dev/null || true
            stopped=true
        fi
        rm -f "$PID_FILE"
    fi

    # Ensure any matching SSH process is terminated
    local pids
    pids=$(pgrep -f "ssh.*${LOCAL_PORT}:127.0.0.1:${REMOTE_PORT}.*${REMOTE_HOST}" || echo "")
    if [[ -n "$pids" ]]; then
        kill $pids 2>/dev/null || true
        stopped=true
    fi

    if $stopped; then
        echo "==> Shore Dashboard tunnel stopped."
    else
        echo "==> Shore Dashboard tunnel is not running."
    fi
}

status_tunnel() {
    if is_running; then
        echo "==> Shore Dashboard tunnel: ACTIVE (127.0.0.1:$LOCAL_PORT -> $REMOTE_HOST:$REMOTE_PORT)"
        local http_code
        http_code=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$LOCAL_PORT/health" 2>/dev/null || echo "DOWN")
        echo "==> Remote HTTP Health: $http_code"
        echo "==> Dashboard URL: http://localhost:$LOCAL_PORT/"
    else
        echo "==> Shore Dashboard tunnel: INACTIVE"
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
