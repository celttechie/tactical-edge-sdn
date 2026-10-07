# 4. Automated Continuous Compliance via Lula & OSCAL

Date: 2026-10-05

## Status
Accepted

## Context
Accreditation of software running in tactical defense environments (DoD IL4/IL5) traditionally requires labor-intensive manual security reviews and static STIG checklists that go out of date immediately after deployment. We need an automated, machine-readable mechanism to validate security posture continuously on edge clusters.

## Decision
1. Implement **Lula** as our compliance engine using the **OSCAL (Open Security Controls Assessment Language)** standard.
2. Define component validation manifests (`oscal-component.yaml` and `compliance/lula/validations/*.yaml`) mapping specific NIST SP 800-53 Rev 5 and DISA STIG controls (container security, network boundary filtering, capability bounding, telemetry monitoring) directly to Kubernetes runtime checks and kernel sysctls.
3. Integrate Lula audit execution into post-deployment scripts and CI/CD pipelines to generate instant, auditable assessment evidence.

## Consequences
- **Positive:**
  - Real-time audit evidence generation for Government ISSMs and security evaluators.
  - Compliance shifts left into the automated build and deployment pipeline.
  - Eliminates drift between documented security policies and running cluster configurations.
- **Negative:**
  - Requires maintaining OSCAL validation logic in sync with evolving STIG benchmarks.
