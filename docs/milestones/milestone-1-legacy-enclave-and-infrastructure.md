# Milestone 1: Multi-Bearer Network Topology & Legacy Emulation

## Objective
Establish the foundational virtual infrastructure on the Dell Precision T5600 hypervisor (using OpenTofu / Libvirt), emulating multi-bearer radio connections and a legacy static-routed shipboard enclave.

## Tasks & Deliverables
- [ ] **Infrastructure as Code (`infra/tofu/`):**
  - Define three isolated Libvirt virtual bridges representing distinct tactical bearers:
    1. `br-pleops`: Simulated P-LEO Satellite Link (Low latency ~40ms, High Bandwidth).
    2. `br-milsat`: Simulated MILSATCOM Link (High latency ~500ms, Moderate Bandwidth).
    3. `br-losrf`: Simulated Line-of-Sight Tactical RF (Variable latency ~100ms, Low Bandwidth).
  - Define shipboard security enclaves (e.g., `br-enclave-unclass` and `br-enclave-secret`).
- [ ] **Legacy Gateway Emulation (`infra/legacy/`):**
  - Deploy a legacy router VM configured with static routes, rigid IPsec tunnel configurations, and fixed metric failover.
  - Demonstrate baseline traffic flow from the enclave VM to an upstream destination (simulated AWS shore endpoint).
- [ ] **Validation Criteria:**
  - Enclave hosts can reach the simulated shore destination over the primary bridge.
  - Manual impairment of the primary bridge demonstrates the legacy failure mode: session stalls and traffic blackholing due to lack of dynamic path re-evaluation.
