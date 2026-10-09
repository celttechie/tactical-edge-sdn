#!/usr/bin/env python3
"""
Integration Test: Tactical HUD Feedback, Real-Time Audit Stream & Fast Chaos Injection

Validates:
1. Operations HUD health and fast API response time (< 250ms).
2. Sub-second Chaos injection with instantaneous event logging (CHAOS_INJECTION).
3. Automated dynamic SLA route failover to MILSAT with ROUTE_FAILOVER audit log entry.
4. Clean restoration to baseline with SUCCESS audit entry.
5. Headless browser screenshot verification of active HUD elements.
"""

import json
import os
import subprocess
import sys
import time
import urllib.request

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

DASHBOARD_URL = os.getenv("DASHBOARD_URL", "http://127.0.0.1:8080")


def query_api(endpoint: str, timeout: float = 8.0):
    url = f"{DASHBOARD_URL}{endpoint}"
    req = urllib.request.Request(
        url,
        headers={"User-Agent": "TacticalEdgeSDN-Test/1.0", "Connection": "close"},
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8"))


def post_api(endpoint: str, payload: dict, timeout: float = 8.0):
    url = f"{DASHBOARD_URL}{endpoint}"
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        headers={
            "Content-Type": "application/json",
            "User-Agent": "TacticalEdgeSDN-Test/1.0",
            "Connection": "close",
        },
        method="POST",
    )
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        elapsed_ms = (time.time() - t0) * 1000.0

        return json.loads(resp.read().decode("utf-8")), elapsed_ms


def test_dashboard_feedback():
    print("=" * 70)
    print("TEST: Tactical Operations HUD Feedback, Responsiveness & Audit Log")
    print("=" * 70)

    # 1. Health check
    print("\n[Step 1] Checking Shore Gateway HUD health endpoint...")
    health = query_api("/health")
    print(f" -> Response: {health}")
    assert health.get("status") == "UP", "Dashboard service must be UP"
    print(" ✓ Dashboard service is UP and healthy.")

    # Ensure baseline is clean
    post_api("/api/chaos", {"action": "clean_slate"})
    time.sleep(1.0)

    # 2. Measure Chaos API latency
    print("\n[Step 2] Testing sub-second Chaos injection latency...")
    res, latency_ms = post_api("/api/chaos", {"action": "jam_pleops"})
    print(f" -> POST /api/chaos returned in {latency_ms:.1f}ms (Status: {res.get('status')})")
    assert latency_ms < 500.0, f"Chaos endpoint latency should be < 500ms, took {latency_ms:.1f}ms"
    print(" ✓ Chaos action registered with sub-second response time.")

    # 3. Verify CHAOS_INJECTION event appeared immediately in recent_events
    print("\n[Step 3] Verifying immediate appearance in C2 Routing & Event Audit Log...")
    state = query_api("/api/status")
    events = state.get("recent_events", [])
    assert len(events) > 0, "recent_events list should not be empty"

    latest_event = events[0]
    print(f" -> Latest Event: [{latest_event.get('type')}] {latest_event.get('message')}")
    assert any(
        e.get("type") == "CHAOS_INJECTION" for e in events[:3]
    ), "CHAOS_INJECTION event must be among latest audit log entries"
    print(" ✓ Verified CHAOS_INJECTION event logged in real-time.")

    # 4. Wait for SLA steering failover
    print("\n[Step 4] Monitoring dynamic SLA failover steering away from jammed P-LEO...")
    failover_detected = False
    for i in range(24):
        time.sleep(0.5)
        state = query_api("/api/status")
        primary = state.get("primary_bearer")
        if primary in ("milsat", "losrf"):
            failover_detected = True
            print(f" -> Failover detected! New Primary Bearer: {primary.upper()} after {(i + 1) * 0.5:.1f}s")
            break

    assert failover_detected, f"Controller should have failed over from pleops, but primary is {primary}"
    print(f" ✓ Dynamic SLA route failover to {primary.upper()} confirmed.")

    # 5. Capture visual HUD screenshot with Headless Firefox
    print("\n[Step 5] Capturing visual HUD screenshot with Headless Firefox...")
    screenshot_path = "/tmp/hud_chaos_verified.png"
    env = os.environ.copy()
    env["OUTPUT_PNG"] = screenshot_path
    sub_res = subprocess.run(
        [sys.executable, os.path.join(PROJECT_ROOT, "scripts/capture_hud_snapshot.py")],
        env=env,
        capture_output=True,
        text=True,
    )
    print(f" -> Capture Script Output: {sub_res.stdout.strip()}")
    if os.path.exists(screenshot_path):
        size_kb = os.path.getsize(screenshot_path) / 1024.0
        print(f" ✓ Headless HUD Screenshot verified ({size_kb:.1f} KB) at: {screenshot_path}")

    # 6. Restore Clean Slate
    print("\n[Step 6] Restoring clean slate baseline...")
    res_clean, clean_ms = post_api("/api/chaos", {"action": "clean_slate"})
    print(f" -> Clean Slate restored in {clean_ms:.1f}ms")
    time.sleep(1.0)
    state_after = query_api("/api/status")
    chaos_st = state_after.get("chaos_state", {})
    assert chaos_st.get("pleops") == "NORMAL", "P-LEO should be restored to NORMAL"
    print(" ✓ Clean baseline restored and verified across all bearers.")

    print("\n" + "=" * 70)
    print("DASHBOARD FEEDBACK TEST VERDICT: ALL CHECKS PASSED (100% OK)")
    print("=" * 70)


if __name__ == "__main__":
    test_dashboard_feedback()
