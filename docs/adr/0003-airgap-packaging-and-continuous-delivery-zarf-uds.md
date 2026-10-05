# 3. Air-Gap Packaging and Continuous Delivery with Zarf & UDS

Date: 2026-10-05

## Status
Accepted

## Context
Deploying software updates to naval vessels and tactical edge environments occurs across air-gapped security boundaries and DDIL network links. Traditional deployment mechanisms relying on live internet registries, Helm repository pulls, or fragile manual disk imaging fail in disconnected environments.

## Decision
1. Package the containerized routing engine, policy daemon, configuration maps, and manifests into a self-contained **Zarf package** (`zarf.yaml`).
2. Integrate the SDN package into a **UDS Bundle** (`uds-bundle.yaml`) alongside core infrastructure capabilities (observability, ingress, identity).
3. Deliver deployment bundles to tactical edge nodes (such as the OrangePi and Libvirt sandbox nodes) strictly via offline media drops (virtual disk / USB block device) without runtime external internet connectivity.

## Consequences
- **Positive:**
  - 100% reproducible, cryptographically verifiable deployments offline.
  - Zero reliance on external OCI registries or internet connectivity at deploy time.
  - Native alignment with modern DoD air-gap delivery and open OCI packaging standards.
- **Negative:**
  - Build phase requires upfront caching of all container base images, binaries, and dependencies.
