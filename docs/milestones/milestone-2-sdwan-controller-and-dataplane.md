# Milestone 2: Cloud-Native SD-WAN Dataplane & Controller

## Objective
Build the modernized, containerized routing node and dynamic policy daemon capable of multi-bearer link probing and automated traffic steering.

## Tasks & Deliverables
- [x] **Containerized Dataplane (`src/dataplane/`):**
  - Package **FRRouting (FRR)** and **WireGuard** baseline with multipath forwarding.
  - Implement dynamic routing hooks and NAT masquerade for tactical enclaves.
- [x] **SD-WAN Policy & Probing Daemon (`src/controller/`):**
  - Develop a lightweight Python service performing dual-mode ICMP / TCP jitter and latency probing across active bearer links.
  - Calculate rolling SLA scores (evaluating packet loss %, RTT jitter, and latency thresholds).
  - Dynamically manipulate Linux kernel routing metrics via Netlink API when a path degrades.
- [ ] **Observability & Prometheus Metrics (`src/controller/`):**
  - Instrument the controller with standard Prometheus exposition format (`/metrics`).
  - Expose per-bearer gauges: `sdn_bearer_latency_seconds`, `sdn_bearer_jitter_seconds`, `sdn_bearer_loss_ratio`, `sdn_bearer_metric`, and `sdn_bearer_score`.
  - Expose failover event counter: `sdn_failover_events_total`.
- [x] **Tactical Operations HUD (`src/dashboard/`):**
  - Real-time dark-theme browser HUD displaying dynamic link states, throughput meters, and interactive chaos buttons.

## Validation Criteria
- Continuous UDP/TCP streaming traffic automatically reroutes to secondary links when primary link latency exceeds thresholds or packet loss occurs.
- Active Prometheus scraper can scrape `http://<router-ip>:8080/metrics` or dedicated metrics port and ingest time-series telemetry.
- Zero dropped connections on active streams during simulated failover.
