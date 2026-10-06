# Milestone 3: Air-Gap Zarf Packaging & OrangePi Edge Deployment

## Objective
Package the containerized SD-WAN routing stack into self-contained Zarf packages and deploy them completely offline to the OrangePi tactical edge unit and local K3s cluster.

## Tasks & Deliverables
- [ ] **Helm Chart Architecture (`packages/helm/tactical-sdn/`):**
  - Create the `tactical-sdn` Helm chart (`Chart.yaml`, `values.yaml`).
  - Template the SD-WAN DaemonSet with host-networking and bounded Linux capabilities (`NET_ADMIN`, `NET_RAW`).
  - Template the controller ConfigMap for dynamic multi-bearer thresholds and shore gateway endpoints.
  - Define environment-specific value overrides (`values-sandbox.yaml`, `values-orangepi.yaml`).
  - Validate with `helm lint` and `helm template`.
- [ ] **Container Hardening & Supply Chain Security:**
  - Multi-stage minimal container build for the dataplane and controller.
  - Strict non-root execution and drop of unnecessary capabilities (`ALL` except `NET_ADMIN`, `NET_RAW`).
  - Generate automated CycloneDX/SPDX SBOM via Syft.
  - Generate vulnerability scanning audit report via Grype/Trivy.
- [ ] **Zarf Air-Gap Packaging (`packages/zarf/`):**
  - Update `zarf.yaml` to deploy `tactical-sdn` via the `charts:` directive referencing the local Helm chart.
  - Build the self-contained `.tar.zst` package archive using `zarf package create`.
  - Package both AMD64 (sandbox) and ARM64 (OrangePi) architectures.
- [ ] **UDS Bundle Definition (`packages/uds/`):**
  - Define `uds-bundle.yaml` combining the SD-WAN package with core infrastructure services (ingress, observability).
- [ ] **Edge Cluster Offline Deployment:**
  - Deploy the built Zarf package offline into the sandbox cluster (`zarf package deploy`).
  - Retain deploy automation ready for physical OrangePi 5 hardware drop upon boot.

## Validation Criteria
- `helm lint` and `helm template` pass with 0 errors.
- `zarf package create` succeeds in generating the `.tar.zst` air-gapped package on disk.
- Offline deployment succeeds into a disconnected cluster with 0 internet calls.
- SBOM and vulnerability scan reports are generated and tracked in `compliance/reports/`.
