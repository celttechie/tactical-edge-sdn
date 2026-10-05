# 2. Dynamic Multipath Overlay and Dataplane Selection

Date: 2026-10-05

## Status
Accepted

## Context
Legacy tactical shipboard routing systems (e.g., ADNS and early CANES baselines) rely on static routing, monolithic VM-based network appliances, and manual satellite link switching. When primary RF/SATCOM paths degrade or experience jamming, static routes cause packet blackholing or prolonged outages. Modern tactical edge deployments require dynamic multi-bearer traffic steering across disparate transport networks (P-LEO satellite, military MILSATCOM, and tactical Line-of-Sight RF) with minimal CPU/memory overhead.

## Decision
1. **Routing Control Plane:** Adopt **FRRouting (FRR)** (specifically BGP/BFD and policy-based routing) containerized as a Cloud-Native Network Function (CNF).
2. **Cryptographic Overlay:** Use **WireGuard** point-to-multipoint dynamic mesh overlays for secure inter-node transport over unclassified/hostile bearer networks.
3. **Link Quality Probing & Telemetry:** Build a lightweight Python/C++ daemon using Linux socket/eBPF metrics to continuously evaluate RTT (Round Trip Time), jitter, and packet loss across active bearers and dynamically adjust Linux routing metrics/BGP weights.

## Consequences
- **Positive:**
  - Lightweight footprint suitable for both embedded edge SBCs (OrangePi) and rackmount hypervisors (Dell T5600).
  - Sub-second failover between simulated bearers without TCP session drops.
  - Elimination of proprietary hardware and monolithic VM appliance licensing.
- **Negative:**
  - Requires Linux kernel capabilities (`NET_ADMIN`, `NET_RAW`) in container definitions, requiring strict STIG and Lula policy validation.
