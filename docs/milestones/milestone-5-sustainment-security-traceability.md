# Milestone 5: Engineering Rigor, Security Traceability & FDE Role Alignment

## Objective
Establish long-term software sustainment discipline, supply chain traceability, and explicit technical documentation mapping the project's engineering decisions directly to the Defense Unicorns Forward Deployed Engineer (FDE) / SDN role requirements.

## Tasks & Deliverables
- [x] **FDE SDN Technical Mapping Guide (`docs/FDE_SDN_TECHNICAL_MAPPING.md`):**
  - Architectural breakdown comparing legacy shipboard routing (ADNS/CANES static routes & VNFs) against cloud-native SD-WAN (CNFs & dynamic steering).
  - Explicit explanation of engineering trade-offs (e.g., userspace socket prober vs eBPF, kernel route mutation vs BGP local-preference, multi-bridge Linux taps vs hardware radios).
  - Concrete breakdown of how every repo artifact maps to the responsibilities in the Defense Unicorns SDN job description.
  - 5-Minute Evaluator Quickstart with reproducible, copy-paste test commands and expected outputs.
- [x] **Software Supply Chain & SBOM Traceability (`compliance/`):**
  - Document all upstream open-source dependencies (FRRouting, WireGuard, Linux Netlink, PyYAML).
  - Generate CycloneDX and SPDX SBOMs for both container images and host binaries.
  - Document automated vulnerability triage and remediation workflows for zero-day CVEs in air-gapped environments (`compliance/vulnerability-management.md`).
- [x] **Automated CI/CD Test Pipeline Definition (`.github/workflows/`):**
  - Establish a GitHub Actions workflow validating:
    1. Python code linting & formatting (`flake8`, `black`, `isort`).
    2. Unit test execution with code coverage reporting (`unittest`, `coverage`).
    3. Helm chart linting (`helm lint`).
    4. Zarf package validation (`zarf.yaml` schema check) and Lula OSCAL linting.

## Validation Criteria
- `docs/FDE_SDN_TECHNICAL_MAPPING.md` is complete, detailed, and directly references codebase symbols and line numbers.
- Automated CI pipeline runs and passes 100% of defined linting, unit test, and packaging checks.
- SBOM and vulnerability artifacts are generated and reproducible via standard tooling (`syft`, `grype`).
