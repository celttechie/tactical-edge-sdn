# Milestone 4: DDIL Chaos Testing & Continuous STIG Compliance

## Objective
Implement an automated DDIL chaos engineering test harness and define Lula OSCAL compliance controls to generate real-time accreditation evidence.

## Tasks & Deliverables
- [x] **Chaos / DDIL Test Harness (`tests/chaos/`):**
  - Linux `tc` / `netem` test runner across virtual bridges and taps (`tests/chaos/impair-bearer.sh`).
  - Scenarios:
    1. *Satellite Rain Fade:* Progressive latency increase to 600ms + 15% packet loss.
    2. *RF Electronic Jamming:* Total sudden blackout of primary bearer with instantaneous recovery.
    3. *Flapping Link:* Bearer cycling on/off every 5 seconds to test route damping algorithms.
  - Interactive chaos triggers integrated into the Tactical Operations HUD.
- [ ] **Quantitative Resiliency Benchmarking Suite:**
  - Automated quantitative benchmark measuring:
    - Time-to-detect link degradation in milliseconds.
    - Convergence duration before secondary link promotion.
    - Total packets dropped vs survived during cutover.
    - Recovery time after bearer restoration.
  - Automated benchmark output generated into `docs/benchmarks/failover-resilience-report.md`.
- [ ] **Executable Lula OSCAL Compliance Validation (`compliance/lula/`):**
  - Define `lula-component.yaml` assessing real container security standards (NIST SP 800-53 / DISA Container STIG):
    - Dropping unnecessary Linux capabilities.
    - Hardened host sysctl network forwarding configurations.
    - Read-only root filesystem and least-privilege runtime.
  - Run `lula validate` against the active cluster/pod and generate real OSCAL assessment results (`assessment-results.yaml`).

## Validation Criteria
- Automated chaos benchmark executes and outputs quantitative resiliency metrics in `docs/benchmarks/failover-resilience-report.md`.
- `lula validate` executes successfully and generates valid OSCAL compliance assessment artifacts with 100% passing controls.
