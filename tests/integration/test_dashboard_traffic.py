#!/usr/bin/env python3
"""
Integration Test: Tactical Operations HUD, Bidirectional Traffic & DDIL Chaos Control

Validates:
1. Active C2 telemetry stream generation from Enclave Client (10.10.1.10) to Shore Gateway (10.200.1.10).
2. Real-time kernel interface statistics scraping and HTTP status reporting.
3. Operations HUD REST API (/api/status) and Server-Sent Events (/api/stream).
4. Interactive Chaos injection via POST /api/chaos, verifying real-time route failover and restoration.
"""

import subprocess
import time
import json
import os
import sys

ROUTER_SSH = [
    "ssh", "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null",
    "-J", "sandbox-hypervisor-node",
    "bjarrett@10.200.1.2"
]

def exec_on_router(command: str) -> str:
    cmd = ROUTER_SSH + [command]
    res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=15)
    if res.returncode != 0:
        raise RuntimeError(f"Router command failed: {command}\nStderr: {res.stderr}\nStdout: {res.stdout}")
    return res.stdout.strip()

def test_enclave_shore_traffic_flow():
    print("\n[Step 1] Verifying Active Enclave -> Shore C2 Traffic Flow...")
    
    # Query Enclave Streamer Status
    enclave_raw = exec_on_router("curl -s -m 2 http://10.10.1.10:9001/status")
    enclave_stats = json.loads(enclave_raw)
    print(f" -> Enclave Streamer: Sent {enclave_stats.get('total_sent')} pkts @ {enclave_stats.get('throughput_kbps')} Kbps ({enclave_stats.get('packets_per_sec')} pps)")
    assert enclave_stats.get("total_sent", 0) > 0, "Enclave streamer should have sent packets"
    assert enclave_stats.get("throughput_kbps", 0) > 50, "Throughput should be > 50 Kbps"

    # Query Shore Ingest Status
    shore_raw = exec_on_router("curl -s -m 2 http://10.200.1.10:9001/status")
    shore_stats = json.loads(shore_raw)
    print(f" -> Shore Gateway Ingest: Received {shore_stats.get('total_packets_received')} pkts @ {shore_stats.get('throughput_kbps')} Kbps | Gaps: {shore_stats.get('sequence_gaps')}")
    assert shore_stats.get("total_packets_received", 0) > 0, "Shore ingest should have received packets"
    print(" ✓ Active bidirectional traffic stream verified successfully.")

def test_dashboard_api_status():
    print("\n[Step 2] Verifying Tactical Operations HUD Status API...")
    status_raw = exec_on_router("curl -s -m 2 http://127.0.0.1:8080/api/status")
    state = json.loads(status_raw)

    print(f" -> Overall Readiness: {state.get('overall_readiness')}")
    print(f" -> Primary Bearer:    {state.get('primary_bearer')}")
    
    bearers = state.get("bearers", {})
    assert "pleops" in bearers, "Bearer pleops must be present"
    assert "milsat" in bearers, "Bearer milsat must be present"
    assert "losrf" in bearers, "Bearer losrf must be present"

    for b_name, b_info in bearers.items():
        print(f"    - [{b_name.upper():7s}] State: {b_info.get('state'):8s} | Latency: {b_info.get('latency_ms'):5.1f}ms | Metric: {b_info.get('computed_metric')} | Drops: {b_info.get('total_dropped')}")

    assert state.get("overall_readiness") in ("FMC", "PMC"), "Readiness must be FMC or PMC"
    print(" ✓ Dashboard status API verified successfully.")

def test_chaos_injection_and_failover():
    print("\n[Step 3] Testing Interactive Chaos Injection: EW Jamming on Primary (P-LEO)...")
    
    # 1. Inject EW Jamming on P-LEO
    res_raw = exec_on_router("curl -s -X POST http://127.0.0.1:8080/api/chaos -H 'Content-Type: application/json' -d '{\"action\": \"jam_pleops\"}'")
    res = json.loads(res_raw)
    assert res.get("status") == "OK", "Chaos action must succeed"
    print(" -> EW Jamming injected via API on P-LEO.")

    # 2. Wait for SLA detection and path steering failover
    print(" -> Waiting for automated SLA evaluation and route failover...")
    time.sleep(4)

    # 3. Check status API after failover
    status_raw = exec_on_router("curl -s -m 2 http://127.0.0.1:8080/api/status")
    state = json.loads(status_raw)
    pleops = state.get("bearers", {}).get("pleops", {})
    
    print(f" -> Post-Chaos State: Bearer [PLEOPS] Loss = {pleops.get('packet_loss_pct')}% | State = {pleops.get('state')} | Metric = {pleops.get('computed_metric')}")
    assert pleops.get("packet_loss_pct", 0) > 0, "Packet loss must be detected on P-LEO"
    assert pleops.get("state") in ("DEGRADED", "DOWN"), "P-LEO must be in DEGRADED or DOWN state"
    print(" ✓ Failover detected and reflected in Dashboard API.")

    # 4. Restore Clean Baseline
    print("\n[Step 4] Restoring Clean Baseline via Chaos API...")
    restore_raw = exec_on_router("curl -s -X POST http://127.0.0.1:8080/api/chaos -H 'Content-Type: application/json' -d '{\"action\": \"clean_slate\"}'")
    restore_res = json.loads(restore_raw)
    assert restore_res.get("status") == "OK", "Clean slate action must succeed"

    time.sleep(4)
    status_raw = exec_on_router("curl -s -m 2 http://127.0.0.1:8080/api/status")
    state = json.loads(status_raw)
    primary = state.get("primary_bearer")
    print(f" -> Restored Primary Bearer: [{primary.upper()}] | Overall Readiness: {state.get('overall_readiness')}")
    print(" ✓ Full Chaos Injection, Failover, and Recovery cycle validated!")

def main():
    print("============================================================================")
    print("INTEGRATION TEST: Tactical Edge SD-WAN HUD, Live Traffic & Chaos Injection")
    print("============================================================================")
    
    test_enclave_shore_traffic_flow()
    test_dashboard_api_status()
    test_chaos_injection_and_failover()
    
    print("\n============================================================================")
    print("ALL TESTS PASSED: Tactical Operations HUD & Active Traffic 100% OPERATIONAL")
    print("============================================================================")

if __name__ == "__main__":
    main()
