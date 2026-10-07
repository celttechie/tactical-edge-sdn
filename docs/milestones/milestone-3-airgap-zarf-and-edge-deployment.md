# Milestone 3: Air-Gap Zarf Packaging & OrangePi Edge Deployment

## Objective
Package the containerized SD-WAN routing stack into self-contained Zarf packages and deploy them completely offline to the OrangePi tactical edge unit and local K3s cluster.

## Tasks & Deliverables
- [x] **Helm Chart Architecture (`packages/helm/tactical-sdn/`):**
  - Create the `tactical-sdn` Helm chart (`Chart.yaml`, `values.yaml`).
  - Template the SD-WAN DaemonSet with host-networking and bounded Linux capabilities (`NET_ADMIN`, `NET_RAW`).
  - Template the controller ConfigMap for dynamic multi-bearer thresholds and shore gateway endpoints.
  - Define environment-specific value overrides (`values-sandbox.yaml`, `values-orangepi.yaml`).
  - Validate with `helm lint` and `helm template`.
- [x] **Container Hardening & Supply Chain Security:**
  - Multi-stage minimal container build for the dataplane and controller.
  - Strict non-root execution and drop of unnecessary capabilities (`ALL` except `NET_ADMIN`, `NET_RAW`).
  - Generate automated CycloneDX/SPDX SBOM via Syft embedded in Zarf package.
  - Verify container security posture against least-privilege standards.
- [x] **Zarf Air-Gap Packaging (`packages/zarf/`):**
  - Update `zarf.yaml` to deploy `tactical-sdn` via the `charts:` directive referencing the local Helm chart.
  - Build the self-contained `.tar.zst` package archive using `zarf package create`.
  - Package AMD64 sandbox release (`tactical-sdn-stack:v0.3.0`).
- [x] **UDS Bundle Definition (`packages/uds/`):**
  - Define `uds-bundle.yaml` combining the SD-WAN package with core infrastructure services (ingress, observability).
- [x] **Edge Cluster Offline Deployment:**
  - Deploy the built Zarf package offline into the sandbox cluster (`zarf package deploy`).
  - Automate node transition via `scripts/modernize-ship-node.sh`.
  - Retain deploy automation ready for physical OrangePi 5 hardware drop upon boot.

## Validation Criteria
- [x] `helm lint` and `helm template` pass with 0 errors.
- [x] `zarf package create` succeeds in generating the `.tar.zst` air-gapped package on disk (`build/zarf-package-tactical-sdn-stack-amd64-0.3.0.tar.zst`).
- [x] Offline deployment succeeds into a disconnected cluster with 0 internet calls (`scripts/verify-ship-modernization.sh`).
- [x] SBOM and package layers verified via automated test harness (`tests/integration/test_zarf_airgap.py`).
