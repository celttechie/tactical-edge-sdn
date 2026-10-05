#!/usr/bin/env bash
# ==============================================================================
# Tactical Edge DDIL Chaos & Link Impairment Harness
# Simulates P-LEO, MILSATCOM, and Tactical RF latency, jitter, loss, and outages
# Targets bridge devices and attached VM tap interfaces in Libvirt
# ==============================================================================

set -euo pipefail

HYPERVISOR_HOST="${HYPERVISOR_HOST:-sandbox-hypervisor-node}"

usage() {
    echo "Usage: $0 [apply-profiles | cut <pleops|milsat|losrf> | restore <pleops|milsat|losrf> | restore-all | status]"
    echo ""
    echo "Commands:"
    echo "  apply-profiles  Apply tactical baseline netem profiles to all 3 bearers"
    echo "  cut <bearer>    Simulate complete blackout/loss (100% packet drop) on a bearer"
    echo "  restore <bearer> Remove impairments and restore clean line on a bearer"
    echo "  restore-all     Clear all netem rules across all bearer bridges and taps"
    echo "  status          Display current tc/netem qdisc configurations"
    exit 1
}

run_on_hypervisor() {
    local cmd="$1"
    ssh "$HYPERVISOR_HOST" "sudo bash -c $(printf %q "$cmd")"
}

get_bridge_interface() {
    local net_name="$1"
    ssh "$HYPERVISOR_HOST" "sudo virsh net-info $net_name 2>/dev/null | grep 'Bridge:' | awk '{print \$2}'"
}

apply_netem_to_bridge_and_taps() {
    local br="$1"
    local netem_args="$2"
    
    # Apply to bridge root
    run_on_hypervisor "tc qdisc replace dev $br root netem $netem_args 2>/dev/null || true"
    
    # Apply to all tap interfaces currently enslaved to the bridge
    run_on_hypervisor "for tap in \$(ip -o link show master $br | cut -d: -f2 | tr -d ' '); do tc qdisc replace dev \$tap root netem $netem_args 2>/dev/null || true; done"
}

clear_netem_on_bridge_and_taps() {
    local br="$1"
    run_on_hypervisor "tc qdisc del dev $br root 2>/dev/null || true; for tap in \$(ip -o link show master $br | cut -d: -f2 | tr -d ' '); do tc qdisc del dev \$tap root 2>/dev/null || true; done"
}

case "${1:-}" in
    apply-profiles)
        echo "==> Applying tactical network profiles across all bearer bridges and taps on $HYPERVISOR_HOST..."
        BR_PLEOPS=$(get_bridge_interface br-pleops)
        BR_MILSAT=$(get_bridge_interface br-milsat)
        BR_LOSRF=$(get_bridge_interface br-losrf)

        echo " -> P-LEO Satellite ($BR_PLEOPS + taps): 25ms +/- 5ms delay, 100Mbps, 0.1% loss"
        apply_netem_to_bridge_and_taps "$BR_PLEOPS" "delay 25ms 5ms distribution normal loss 0.1% rate 100mbit"

        echo " -> MILSATCOM ($BR_MILSAT + taps): 250ms +/- 25ms delay, 10Mbps, 0.5% loss"
        apply_netem_to_bridge_and_taps "$BR_MILSAT" "delay 250ms 25ms distribution normal loss 0.5% rate 10mbit"

        echo " -> Tactical LOS RF ($BR_LOSRF + taps): 50ms +/- 10ms delay, 5Mbps, 1.0% loss"
        apply_netem_to_bridge_and_taps "$BR_LOSRF" "delay 50ms 10ms distribution normal loss 1.0% rate 5mbit"
        echo "==> Profiles applied successfully."
        ;;

    degrade)
        BEARER="${2:-}"
        DELAY="${3:-300ms 50ms}"
        LOSS="${4:-15%}"
        if [[ -z "$BEARER" ]]; then usage; fi
        BR_DEV=$(get_bridge_interface "br-$BEARER")
        echo "==> Degrading bearer $BEARER ($BR_DEV + taps) with delay $DELAY and loss $LOSS..."
        apply_netem_to_bridge_and_taps "$BR_DEV" "delay $DELAY loss $LOSS"
        echo "==> Link $BEARER degraded."
        ;;

    cut)
        BEARER="${2:-}"
        if [[ -z "$BEARER" ]]; then usage; fi
        BR_DEV=$(get_bridge_interface "br-$BEARER")
        echo "==> Simulating complete link severance (100% packet loss) on $BEARER ($BR_DEV + taps)..."
        apply_netem_to_bridge_and_taps "$BR_DEV" "loss 100%"
        echo "==> Link $BEARER severed."
        ;;

    restore)
        BEARER="${2:-}"
        if [[ -z "$BEARER" ]]; then usage; fi
        BR_DEV=$(get_bridge_interface "br-$BEARER")
        echo "==> Restoring clean link on $BEARER ($BR_DEV + taps)..."
        clear_netem_on_bridge_and_taps "$BR_DEV"
        echo "==> Link $BEARER restored."
        ;;

    restore-all)
        echo "==> Clearing all impairments across all bearer bridges and tap interfaces..."
        for b in pleops milsat losrf; do
            BR_DEV=$(get_bridge_interface "br-$b" || echo "")
            if [[ -n "$BR_DEV" ]]; then
                echo " -> Restoring br-$b ($BR_DEV + taps)..."
                clear_netem_on_bridge_and_taps "$BR_DEV"
            fi
        done
        echo "==> All bridges and taps reset to clean state."
        ;;

    status)
        echo "==> Current tc qdisc status on $HYPERVISOR_HOST:"
        for b in pleops milsat losrf; do
            BR_DEV=$(get_bridge_interface "br-$b" || echo "")
            if [[ -n "$BR_DEV" ]]; then
                echo "--- br-$b ($BR_DEV) ---"
                run_on_hypervisor "tc -s qdisc show dev $BR_DEV; for tap in \$(ip -o link show master $BR_DEV | cut -d: -f2 | tr -d ' '); do echo \"  tap: \$tap\"; tc -s qdisc show dev \$tap; done"
            fi
        done
        ;;

    *)
        usage
        ;;
esac
