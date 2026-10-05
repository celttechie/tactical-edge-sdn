# Milestone 2: Cloud-Native SD-WAN Dataplane & Controller

## Objective
Build the modernized, containerized routing node and dynamic policy daemon capable of multi-bearer link probing and automated traffic steering.

## Tasks & Deliverables
- [ ] **Containerized Dataplane (`src/dataplane/`):**
  - Package **FRRouting (FRR)** and **WireGuard** into an OCI container image.
  - Configure BGP with Bidirectional Forwarding Detection (BFD) and policy-based routing tables for multi-path forwarding.
  - Implement point-to-multipoint encrypted WireGuard overlays across all active bearers.
- [ ] **SD-WAN Policy & Probing Daemon (`src/controller/`):**
  - Develop a lightweight Python / C++ service that performs continuous ICMP / UDP jitter probing across active bearer links.
  - Calculate rolling SLA scores (evaluating packet loss %, RTT jitter, and latency thresholds).
  - Dynamically manipulate Linux kernel multipath weights or BGP local preference via Netlink API when a path degrades.
- [ ] **Validation Criteria:**
  - Continuous UDP/TCP streaming traffic automatically reroutes to secondary links when primary link latency exceeds 150ms or packet loss exceeds 5%.
  - Zero dropped connections on active TCP streams during simulated failover.
