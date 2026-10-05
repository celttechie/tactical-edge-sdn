# Milestone 3: Air-Gap Zarf Packaging & OrangePi Edge Deployment

## Objective
Package the containerized SD-WAN routing stack into self-contained Zarf packages and deploy them completely offline to the OrangePi tactical edge unit and local K3s cluster.

## Tasks & Deliverables
- [ ] **Zarf Package Construction (`packages/zarf/`):**
  - Define `zarf.yaml` containing the routing container image, controller binary, configuration Helm charts/manifests, and health check scripts.
  - Build the self-contained package archive (`zarf package create`).
- [ ] **UDS Bundle Definition (`packages/uds/`):**
  - Define `uds-bundle.yaml` combining the SD-WAN package with core infrastructure services (ingress, observability).
- [ ] **Hardware Edge Deployment (OrangePi 5):**
  - Bootstrap a standalone, offline K3s instance on the OrangePi.
  - Transfer the built Zarf package via secondary virtual block media / offline storage.
  - Execute `zarf package deploy` completely disconnected from the internet.
- [ ] **Validation Criteria:**
  - Full SDN stack deploys and becomes operational on the OrangePi with 0 external network requests.
  - OrangePi establishes an encrypted WireGuard SD-WAN tunnel back to the T5600 core cluster.
