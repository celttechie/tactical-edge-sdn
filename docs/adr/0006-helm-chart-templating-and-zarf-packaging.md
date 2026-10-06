# 6. Helm-Based Configuration Management for Air-Gapped Zarf Deployment

Date: 2026-10-06

## Status
Accepted

## Context
As the project evolved to support automated multi-bearer routing and dynamic telemetry across varied hardware targets (e.g., Libvirt virtual machines, Talos Kubernetes nodes, and physical ARM64 OrangePi units), managing static Kubernetes manifests via raw Kustomize files created maintenance overhead:
1. **Hardcoded Topology**: Interface names, subnet ranges (`shore_subnet`, `enclave_subnet`), and bearer metrics were duplicated across multiple YAML files (`configmap.yaml`, `daemonset.yaml`).
2. **Multi-Environment Variances**: Deploying to the local sandbox requires different resource requests, host interface mounts, and container registries than deploying to an edge ARM64 device or a cluster node.
3. **Zarf Native Packaging Integration**: Zarf provides first-class support for Helm charts, allowing automated extraction and vendoring of container images, values override cascading, and release lifecycle management during air-gapped `zarf package create` and `zarf package deploy`.

## Decision
1. **Transition Kubernetes Manifests to a Native Helm Chart**:
   - Establish a centralized Helm chart (`packages/helm/tactical-sdn`) encapsulating the SDN controller DaemonSet, configuration ConfigMap, and telemetry Service.
   - Externalize all runtime parameters (bearer interfaces, SLA latency/jitter/loss thresholds, probe frequencies, and container images) into `values.yaml`.
   - Provide environment-specific values overlays (e.g., `values-sandbox.yaml`, `values-edge-arm64.yaml`).

2. **Integrate Helm Directly into Zarf (`zarf.yaml`)**:
   - Replace raw Kustomize manifest definitions in `packages/zarf/zarf.yaml` with the `charts:` directive referencing `packages/helm/tactical-sdn`.
   - Leverage Zarf's built-in container image discovery to bundle the containerized dataplane and controller images directly into the offline `.tar.zst` package.

3. **Maintain Two-Tier Deployment Capability**:
   - **Tier 1 (Host-Native / VM)**: OpenTofu + Cloud-Init for virtualized hypervisor lab topologies.
   - **Tier 2 (Cloud-Native / CNF)**: Helm + Zarf for containerized edge Kubernetes nodes (Talos / K3s / OrangePi).

## Consequences
- **Positive:**
  - Single source of truth for all SDN configuration variables in `values.yaml`.
  - Reusable across multiple edge deployment targets without rewriting YAML manifests.
  - Native image discovery and air-gap distribution using Zarf without external registry access at deployment time.
  - Clean upgrade, rollback, and uninstallation semantics managed via Helm / Zarf release tracking.
- **Negative:**
  - Introduces Helm chart templating syntax (`{{ .Values... }}`) to maintain alongside Python controller code.
  - Requires maintaining Helm chart linting and template validation in CI/CD.
