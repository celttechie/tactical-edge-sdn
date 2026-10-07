# 7. Real-Time Operations HUD Modernization Lifecycle & Interactive Day 0-to-Day 2 Gateway Control

Date: 2026-10-07

## Status
Accepted

## Context
Project Overmatch-Edge demonstrates the modernization of legacy tactical shipboard networking (monolithic VNFs with static metric routing) into a cloud-native, containerized SD-WAN architecture (Kubernetes CNF with dynamic Netlink SLA path steering).

Previously, the Tactical Operations HUD (`src/dashboard/`):
1. Assumed the shipboard gateway was already modernized to the containerized CNF (`tactical-sdn`) and did not visually represent the "Day 0" legacy baseline state.
2. Did not surface the progressive lifecycle states of shipboard transformation:
   - **Stage 1 (Day 0 Legacy Baseline)**: Legacy systemd router running static metrics; no Kubernetes cluster present.
   - **Stage 2 (K3s Bootstrap)**: Background air-gapped lightweight Kubernetes cluster initialization while legacy routing remains live.
   - **Stage 3 (Zarf Staging & Offline Registry)**: Zarf seed registry, webhook agents, and container package staging.
   - **Stage 4 (CNF Deployment & Atomic Hot Cutover)**: SD-WAN CNF container rollout, SLA health verification, atomic retirement of legacy routing, and conntrack flush.
3. Required operators and evaluators to trigger modernization transitions exclusively via CLI scripts (`scripts/modernize-ship-node.sh`), without real-time visual progress or interactive one-click stage controls on the Operations HUD.

## Decision
1. **Model Modernization Lifecycle States in Dashboard Backend (`src/dashboard/server.py`)**:
   - Introduce a structured `modernization_lifecycle` status object queried from the live gateway node or managed statefully:
     - `stage`: `STAGE_1_LEGACY_DAY0`, `STAGE_2_K3S_INIT`, `STAGE_3_ZARF_STAGING`, `STAGE_4_CNF_ACTIVE`.
     - `gateway_type`: `LEGACY_VNF` vs `CONTAINERIZED_CNF`.
     - `k3s_status`: `STOPPED`, `INITIALIZING`, `READY`.
     - `zarf_status`: `UNINITIALIZED`, `SEEDING`, `REGISTRY_READY`.
     - `cnf_status`: `NOT_DEPLOYED`, `STARTING`, `HEALTHY`.
     - `routing_mode`: `STATIC_METRIC_ROUTING` vs `DYNAMIC_SLA_STEERING`.
   - Add REST API endpoints:
     - `GET /api/modernization`: Returns current modernization stage, detailed component states, and execution logs.
     - `POST /api/modernization/step`: Triggers individual modernization lifecycle stages or step-by-step progress (`bootstrap_k3s`, `init_zarf`, `deploy_cnf_cutover`, `reset_day0`).

2. **Enhance Operations HUD UI (`src/dashboard/static/`)**:
   - **Day 0 vs Day 2 Gateway Visualization**: The animated topology canvas visually differentiates between the monolithic Legacy VNF router (`[LEGACY ROUTER 10.200.1.2]`) and the modernized K3s Cloud-Native CNF (`[SD-WAN CNF 10.200.1.2]`).
   - **Modernization Stepper & Progress Pipeline Banner**: Add a prominent visual lifecycle stepper tracking:
     `[1. Legacy Baseline] ➔ [2. K3s Bootstrap] ➔ [3. Zarf Staging] ➔ [4. Atomic Hot Cutover]`.
   - **Interactive Modernization Control Buttons**:
     Provide interactive control buttons in an operator panel:
     - "Step 1: Bootstrap K3s"
     - "Step 2: Initialize Zarf Registry"
     - "Step 3: Atomic Cutover to CNF"
     - "Full Upgrade (Autonomous)"
     - "Rollback / Reset to Day 0"
   - Live audit logging in the HUD event console reflecting every milestone transition in real-time.

3. **Synchronize Telemetry & Routing Behavior Across Stages**:
   - In **Stage 1 (Day 0 Legacy Baseline)**, the HUD displays static metric routing behavior with gray-failure vulnerability indicators.
   - In **Stages 2 and 3**, the HUD highlights that legacy routing remains continuous while cluster components pre-stage in the background (zero downtime).
   - In **Stage 4**, the HUD activates full dynamic SLA path steering, Prometheus `/metrics`, and resilience benchmarking.

4. **Docked Mission Control Sidebar (Upgrades, Chaos, Live Logs)**:
   - **Streamlined Main Dashboard View**: The main dashboard is strictly dedicated to displaying live operational posture, dynamic topology, bearer quality metrics, resilience benchmarks, and tactical audit logs. All operational controls (modernization stepper triggers, DDIL chaos impairment injection, and live execution logs) are consolidated into a docked sidebar.
   - **Docked Push-Shift Layout**:
     - Rather than obscuring dashboard visualizations behind a modal or dark backdrop, the sidebar docks on the right side of the screen (`margin-right: 520px;`).
     - On desktop viewports, the main dashboard layout resizes smoothly beside the sidebar, allowing operators to trigger upgrades or inject chaos while directly observing packet flows, bearer metrics, and SLA failovers in real time.
   - **Three-Page Tabbed Mission Control Navigation**:
     - **Tab 1: UPGRADE**: Current gateway posture status card, active transition progress, and all 5 modernization buttons (`RESET TO DAY 0`, `STEP 1: BOOTSTRAP K3s`, `STEP 2: INIT ZARF REGISTRY`, `STEP 3: ATOMIC HOT CUTOVER`, `FULL AUTONOMOUS UPGRADE`).
     - **Tab 2: CHAOS**: DDIL and EW impairment injection controls (`EW JAMMING ATTACK`, `SATELLITE RAIN FADE`, `RF MULTIPATH / JAM`, `LINK FLAP SIMULATOR`, `RESTORE CLEAN SLATE`, `APPLY TACTICAL PROFILES`).
     - **Tab 3: LOGS**: Real-time backend execution log feed with subsystem filter pills (`ALL`, `MODERNIZER`, `CMD`, `PROBER`, `SLA-ENGINE`, `CHAOS`), search bar, auto-scroll toggle, clear buffer, and one-click clipboard copy.
   - **Multi-Surface Access & Global Hotkeys**:
     - Quick-launch header buttons: `[🚀 UPGRADE]`, `[⚡ CHAOS]`, `[📟 LOGS <badge>]`.
     - Right-viewport vertical dock strip pinned to the edge: `[🚀 UPGRADE]`, `[⚡ CHAOS]`, `[📟 LOGS <badge>]`.
     - Global hotkeys: `U` or `1` for Upgrade, `C` or `2` for Chaos, `L` or `3` for Logs, `Escape` to collapse.
   - **Thread-Safe In-Memory Ring Buffer**: Implemented a 2000-entry sliding log buffer in `DashboardDataManager` capturing timestamps (Zulu time), source subsystem (`MODERNIZER`, `PROBER`, `CMD`, `SLA-ENGINE`, `CHAOS`, `SYSTEM`), log level (`INFO`, `CMD`, `SUCCESS`, `WARN`, `ERROR`, `STDOUT`), and messages with REST endpoints `GET /api/logs` and `POST /api/logs/clear`.

## Consequences
- **Positive:**
  - The main dashboard remains uncluttered and solely focused on telemetry, packet flows, and SLA steering visualization.
  - The docked push-shift sidebar eliminates visual obstruction, allowing operators to trigger chaos or modernization while observing live failover dynamics.
  - Unified Mission Control sidebar consolidates upgrading, chaos injection, and logs under one coherent interface with intuitive tabs and keyboard shortcuts.
  - Subprocess stdout/stderr output is visible live as commands execute, eliminating uncertainty during multi-step upgrades or cluster deployments.
- **Negative:**
  - In-memory ring buffer consumes a small amount of daemon memory (capped at 2000 lines).
  - Background polling adds lightweight HTTP requests (every 1s when logs tab is open, 5s when closed).
