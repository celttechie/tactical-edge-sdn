# Milestone 4: DDIL Chaos Testing & Continuous STIG Compliance

## Objective
Implement an automated DDIL chaos engineering test harness and define Lula OSCAL compliance controls to generate real-time accreditation evidence.

## Tasks & Deliverables
- [ ] **Chaos / DDIL Test Suite (`tests/chaos/`):**
  - Develop an automated Python test runner interacting with Linux `tc` / `netem` across virtual bridges.
  - Test Scenarios:
    1. *Satellite Rain Fade:* Progressive latency increase from 40ms to 600ms + 15% packet loss.
    2. *RF Electronic Jamming:* Total sudden blackout of primary bearer with instantaneous recovery.
    3. *Flapping Link:* Bearer cycling on/off every 5 seconds to test route damping algorithms.
  - Measure and record SLA recovery times and packet loss metrics.
- [ ] **Lula OSCAL Compliance Manifests (`compliance/lula/`):**
  - Define `lula-component.yaml` assessing container security standards (NIST SP 800-53 controls, DISA Container Hardening STIG):
    - Non-root container execution (UID != 0).
    - Read-only root filesystem enforcement.
    - Strict drop of all unnecessary Linux capabilities (retaining only required networking caps).
    - Hardened host kernel sysctl settings.
  - Run `lula validate` and output compliance assessment documentation.
- [ ] **Validation Criteria:**
  - Automated chaos test suite executes and outputs a quantitative resiliency benchmark report.
  - `lula validate` passes 100% of defined STIG controls against the running cluster.
