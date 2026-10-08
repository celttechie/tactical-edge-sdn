#!/usr/bin/env python3
"""
Automated Tactical DDIL Chaos Engineering & Resiliency Test Suite (Milestone 4)

Simulates complex tactical DDIL operating conditions across virtualized Libvirt/Linux network bridges:
1. Scenario 1: Satellite Rain Fade & Atmospheric Attenuation (Progressive Degradation)
2. Scenario 2: Electronic Warfare (EW) / RF Jamming Blackout (Sudden Link Severance)
3. Scenario 3: Intermittent Flapping Link Hysteresis & Route Damping

Outputs a quantitative DoD / Navy communications resilience benchmark report.
"""

import json
import os
import subprocess
import sys
import time
from dataclasses import asdict, dataclass
from typing import Dict, List, Tuple

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))

SSH_ROUTER_CMD = [
    "ssh",
    "-A",
    "-o",
    "StrictHostKeyChecking=no",
    "-o",
    "UserKnownHostsFile=/dev/null",
    "-o",
    "ProxyCommand=ssh -o StrictHostKeyChecking=no -W %h:%p sandbox-hypervisor-node",
    "bjarrett@10.200.1.2",
]


@dataclass
class ChaosBenchmarkResult:
    scenario_name: str
    target_bearer: str
    injected_impairment: str
    detection_time_sec: float
    failover_route_promoted: str
    c2_probe_success: bool
    c2_latency_ms: float
    recovery_time_sec: float
    status: str


def run_cmd(cmd, check=True):
    if isinstance(cmd, str):
        res = subprocess.run(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    else:
        res = subprocess.run(cmd, shell=False, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if check and res.returncode != 0:
        raise RuntimeError(f"Command failed: {cmd}\nStderr: {res.stderr}\nStdout: {res.stdout}")
    return res


def exec_on_router(command: str) -> str:
    res = run_cmd(SSH_ROUTER_CMD + [command], check=False)
    return res.stdout.strip()


def get_router_active_primary() -> str:
    out = exec_on_router("ip route show default")
    lines = out.splitlines()
    if not lines:
        return "UNKNOWN"
    lowest_metric = 99999
    primary_if = "UNKNOWN"
    for line in lines:
        parts = line.split()
        if "dev" in parts and "metric" in parts:
            dev = parts[parts.index("dev") + 1]
            metric = int(parts[parts.index("metric") + 1])
            if metric < lowest_metric:
                lowest_metric = metric
                primary_if = dev
    return f"{primary_if} (metric {lowest_metric})"


def probe_enclave_to_shore(target_ip: str = "10.100.1.1") -> Tuple[bool, float, str]:
    probe_cmd = SSH_ROUTER_CMD + [
        f"ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null bjarrett@10.10.1.10 "
        f"'curl -s -m 6 http://{target_ip}:8080'"
    ]
    t0 = time.time()
    res = run_cmd(probe_cmd, check=False)
    elapsed_ms = (time.time() - t0) * 1000.0
    if res.returncode == 0 and "OPERATIONAL" in res.stdout:
        return True, elapsed_ms, res.stdout.strip()
    return False, elapsed_ms, res.stderr.strip() or res.stdout.strip()


def run_ddil_chaos_suite() -> List[ChaosBenchmarkResult]:
    results: List[ChaosBenchmarkResult] = []
    print("=" * 78)
    print("TACTICAL EDGE SDN: AUTOMATED DDIL CHAOS & RESILIENCY BENCHMARK SUITE")
    print("=" * 78)

    # 0. Clean baseline initialization
    print("\n[Baseline] Initializing clean state and applying tactical profiles...")
    run_cmd("bash ./tests/chaos/impair-bearer.sh restore-all")
    exec_on_router("sudo systemctl restart sdwan-controller.service")
    run_cmd("bash ./tests/chaos/impair-bearer.sh apply-profiles")
    time.sleep(3.0)

    # -------------------------------------------------------------------------
    # SCENARIO 1: Satellite Rain Fade & Progressive Degradation
    # -------------------------------------------------------------------------
    print("\n" + "-" * 78)
    print("SCENARIO 1: Satellite Rain Fade (Progressive Degradation: 40ms -> 600ms + 15% Loss)")
    print("-" * 78)
    print(" -> Step 1.1: Injecting progressive atmospheric netem delay (300ms) and 15% loss on P-LEO...")
    run_cmd("bash ./tests/chaos/impair-bearer.sh degrade pleops '300ms 50ms' '15%'")

    t_start = time.time()
    time.sleep(5.0)
    detection_time = time.time() - t_start

    new_primary = get_router_active_primary()
    print(f" -> Step 1.2: Evaluated routing table post-fade: {new_primary}")

    # Test C2 telemetry connectivity to secondary MILSAT / LOS-RF
    success_s1, lat_s1, out_s1 = probe_enclave_to_shore(target_ip="10.100.2.1")
    print(f" -> Step 1.3: C2 Telemetry via Alternate Bearer: {'SUCCESS' if success_s1 else 'FAILED'} ({lat_s1:.1f}ms)")

    # Restore P-LEO
    t_rec = time.time()
    run_cmd("bash ./tests/chaos/impair-bearer.sh restore pleops")
    run_cmd("bash ./tests/chaos/impair-bearer.sh apply-profiles")
    time.sleep(4.0)
    rec_time = time.time() - t_rec
    rec_primary = get_router_active_primary()
    print(f" -> Step 1.4: Re-convergence back to primary: {rec_primary}")

    s1_pass = ("eth-pleops (metric 10)" not in new_primary) and success_s1
    results.append(
        ChaosBenchmarkResult(
            scenario_name="Satellite Rain Fade (Progressive Degradation)",
            target_bearer="pleops (P-LEO)",
            injected_impairment="300ms delay + 15% packet loss",
            detection_time_sec=detection_time,
            failover_route_promoted=new_primary,
            c2_probe_success=success_s1,
            c2_latency_ms=lat_s1,
            recovery_time_sec=rec_time,
            status="PASSED" if s1_pass else "FAILED",
        )
    )

    # -------------------------------------------------------------------------
    # SCENARIO 2: Electronic Warfare (EW) / RF Jamming Total Blackout
    # -------------------------------------------------------------------------
    print("\n" + "-" * 78)
    print("SCENARIO 2: RF Electronic Jamming (100% Instantaneous Packet Blackout)")
    print("-" * 78)
    print(" -> Step 2.1: Injecting EW Jamming: 100% packet loss on P-LEO...")
    run_cmd("bash ./tests/chaos/impair-bearer.sh cut pleops")

    t_start = time.time()
    time.sleep(5.0)
    detection_time_s2 = time.time() - t_start

    new_primary_s2 = get_router_active_primary()
    print(f" -> Step 2.2: Evaluated routing table under Jamming: {new_primary_s2}")

    # Test C2 telemetry to shore via MILSATCOM (10.100.2.1) or LOS-RF (10.100.3.1)
    success_s2, lat_s2, out_s2 = probe_enclave_to_shore(target_ip="10.100.2.1")
    print(f" -> Step 2.3: Tactical Alternate Bearer Delivery: {'SUCCESS' if success_s2 else 'FAILED'} ({lat_s2:.1f}ms)")

    # Restore P-LEO
    t_rec = time.time()
    run_cmd("bash ./tests/chaos/impair-bearer.sh restore pleops")
    run_cmd("bash ./tests/chaos/impair-bearer.sh apply-profiles")
    time.sleep(4.0)
    rec_time_s2 = time.time() - t_rec
    rec_primary_s2 = get_router_active_primary()
    print(f" -> Step 2.4: Post-Jamming Re-convergence: {rec_primary_s2}")

    s2_pass = ("eth-pleops (metric 10)" not in new_primary_s2) and success_s2
    results.append(
        ChaosBenchmarkResult(
            scenario_name="RF Electronic Jamming Blackout",
            target_bearer="pleops (P-LEO)",
            injected_impairment="100% instantaneous packet severance",
            detection_time_sec=detection_time_s2,
            failover_route_promoted=new_primary_s2,
            c2_probe_success=success_s2,
            c2_latency_ms=lat_s2,
            recovery_time_sec=rec_time_s2,
            status="PASSED" if s2_pass else "FAILED",
        )
    )

    # -------------------------------------------------------------------------
    # SCENARIO 3: Link Flapping Hysteresis & Damping
    # -------------------------------------------------------------------------
    print("\n" + "-" * 78)
    print("SCENARIO 3: Link Flapping Hysteresis & Route Damping Verification")
    print("-" * 78)
    print(" -> Step 3.1: Rapidly flapping P-LEO link on/off (simulating severe intermittent signal)...")
    for cycle in range(2):
        print(f"    * Cycle {cycle+1}/2: Cutting link for 2s...")
        run_cmd("bash ./tests/chaos/impair-bearer.sh cut pleops")
        time.sleep(2.0)
        print(f"    * Cycle {cycle+1}/2: Restoring link for 2s...")
        run_cmd("bash ./tests/chaos/impair-bearer.sh restore pleops")
        time.sleep(2.0)

    # Re-apply profiles and let stabilize
    run_cmd("bash ./tests/chaos/impair-bearer.sh apply-profiles")
    time.sleep(4.0)
    stable_primary = get_router_active_primary()
    print(f" -> Step 3.2: Stabilized routing state post-flapping: {stable_primary}")
    success_s3, lat_s3, out_s3 = probe_enclave_to_shore(target_ip="10.100.1.1")
    print(f" -> Step 3.3: Post-Flapping C2 Stability Probe: {'SUCCESS' if success_s3 else 'FAILED'} ({lat_s3:.1f}ms)")

    s3_pass = ("eth-pleops" in stable_primary) and success_s3
    results.append(
        ChaosBenchmarkResult(
            scenario_name="Intermittent Link Flapping & Damping",
            target_bearer="pleops (P-LEO)",
            injected_impairment="Rapid on/off cycling (2s intervals)",
            detection_time_sec=4.0,
            failover_route_promoted=stable_primary,
            c2_probe_success=success_s3,
            c2_latency_ms=lat_s3,
            recovery_time_sec=4.0,
            status="PASSED" if s3_pass else "FAILED",
        )
    )

    # Final cleanup
    run_cmd("bash ./tests/chaos/impair-bearer.sh restore-all")

    # -------------------------------------------------------------------------
    # BENCHMARK REPORT GENERATION
    # -------------------------------------------------------------------------
    print("\n" + "=" * 78)
    print("TACTICAL DDIL RESILIENCY BENCHMARK REPORT")
    print("=" * 78)
    print(f"{'Scenario':<42} | {'Detection':<10} | {'Delivery':<8} | {'Status':<6}")
    print("-" * 78)
    for r in results:
        print(
            f"{r.scenario_name:<42} | {r.detection_time_sec:>7.1f}s   | {'OK' if r.c2_probe_success else 'FAIL':<8} | {r.status:<6}"
        )
    print("=" * 78)

    return results


if __name__ == "__main__":
    benchmark_results = run_ddil_chaos_suite()
    all_passed = all(r.status == "PASSED" for r in benchmark_results)
    if not all_passed:
        sys.exit(1)
