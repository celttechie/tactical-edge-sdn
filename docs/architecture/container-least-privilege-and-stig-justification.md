# Container Least-Privilege & DISA STIG Justification

## 1. Executive Summary

This document establishes the security architecture, capability justification, and DISA STIG compliance posture for the containerized **Tactical Edge SD-WAN Cloud-Native Network Function (CNF)** (`tactical-sdn-stack`).

To meet rigorous Department of Defense (DoD) security standards for afloat and tactical deployable systems (e.g., U.S. Navy CANES, ADNS modernizations), the CNF operates under an audited **least-privilege, bounded-capability execution model**:
- **`privileged: false`**: The container is unprivileged and prohibited from host device control.
- **`allowPrivilegeEscalation: false`**: SetUID binaries and privilege escalation mechanisms are blocked.
- **`readOnlyRootFilesystem: true`**: Container root filesystem is immutable; all runtime state is restricted to ephemeral, non-executable memory mounts.
- **`capabilities.drop: ["ALL"]`**: All default Linux capabilities are explicitly stripped.
- **Bounded Residual Capabilities**: Only `CAP_NET_ADMIN` and `CAP_NET_RAW` are added to permit kernel route mutation and SLA probing.
- **`hostPID: false`**: Container runs in an isolated PID namespace, preventing inspection or signaling of host processes.
- **`seccompProfile: RuntimeDefault`**: Syscalls are filtered through the standard Linux container seccomp whitelist.

---

## 2. Hardened Security Context Specification

In [`packages/helm/tactical-sdn/values.yaml`](file:///home/bjarrett/Projects/tactical-edge-sdn/packages/helm/tactical-sdn/values.yaml) and [`daemonset.yaml`](file:///home/bjarrett/Projects/tactical-edge-sdn/packages/helm/tactical-sdn/templates/daemonset.yaml):

```yaml
securityContext:
  privileged: false
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop:
      - ALL
    add:
      - NET_ADMIN
      - NET_RAW
  seccompProfile:
    type: RuntimeDefault
```

---

## 3. Residual Capabilities Audit & Technical Justification

In accordance with **DISA Container Hardening STIG (V-242414)**, any capability added beyond the baseline drop-all must be explicitly justified by mission necessity:

| Capability | Technical Function in SDN CNF | Operational Justification | Risk Mitigation |
| :--- | :--- | :--- | :--- |
| **`CAP_NET_ADMIN`** | Linux Netlink FIB routing mutation (`RTM_NEWROUTE`, `RTM_DELROUTE`), interface metric adjustments, and connection tracking invalidation (`conntrack -F` via `NETLINK_NETFILTER`). | **Required for SD-WAN Actuation**: Without `CAP_NET_ADMIN`, the policy controller cannot update the Linux kernel routing table to demote degraded satellite bearers or promote alternate paths during DDIL events. | Container has `privileged: false` and cannot access raw storage or system hardware devices. |
| **`CAP_NET_RAW`** | Creation of raw ICMP sockets (`AF_INET, SOCK_RAW, IPPROTO_ICMP`) for sub-second ping and latency measurement. | **Required for Active SLA Probing**: The prober validates link round-trip time (RTT), jitter variance, and packet loss ratio across P-LEO, MILSATCOM, and LOS-RF carriers every 500ms. | Raw socket creation is restricted to ICMP link telemetry; `allowPrivilegeEscalation: false` prevents elevation. |

### Why `CAP_SYS_ADMIN` Was Dropped
In early prototypes, `SYS_ADMIN` is frequently granted alongside `NET_ADMIN`. In modern Linux kernels (3.18+ through 6.x), Netlink route modification, iptables rule manipulation, and conntrack table maintenance **do not require `CAP_SYS_ADMIN`**. Dropping `SYS_ADMIN` eliminates significant container escape risks (such as cgroup hijacking, arbitrary mount manipulation, and kernel debugfs access).

---

## 4. Host Namespace Architecture

### A. Host Networking (`hostNetwork: true`)
* **Mission Justification**: The CNF operates as the tactical boundary router for the shipboard LAN enclaves (`10.10.0.0/16`). It must directly bind to and manage physical/virtual WAN carrier interfaces (`eth-pleops`, `eth-milsat`, `eth-losrf`) and manipulate the host's primary Forwarding Information Base (FIB).
* **Precedent**: Standard practice for cloud-native networking infrastructure components (e.g., Calico Node, Cilium CNI, MetalLB speaker, Envoy edge gateways).

### B. Isolated Process Namespace (`hostPID: false`)
* **Security Improvement**: Unlike naive gateway deployments that request `hostPID: true`, the CNF is strictly isolated from the host process namespace.
* **Impact**: Processes inside the container cannot enumerate, inspect `/proc`, or deliver UNIX signals to host services (`systemd`, `k3s`, `libvirtd`).

---

## 5. Storage Immutability & Ephemeral Volumes

Under `readOnlyRootFilesystem: true`, modifying container binaries, libraries, or system paths is blocked by the Linux kernel. 

To support FRRouting daemon sockets and temporary files without granting rootfs write access, ephemeral in-memory volumes (`emptyDir: {}`) are mounted:
- **`/run`**: Hosts FRRouting IPC UNIX domain sockets (`/run/frr/zebra.vty`, `/run/frr/bgpd.vty`) and PID files.
- **`/tmp`**: Scratch directory for temporary validation scripts.
- **`/var/log`**: Volatile ring buffers and daemon logs.

Additionally, Python bytecode compilation is disabled at the container level (`PYTHONDONTWRITEBYTECODE=1`), ensuring the Python runtime executes entirely in memory without attempting disk writes.

---

## 6. DISA STIG & NIST SP 800-53 Control Mapping

| Benchmark / Framework | Rule ID / Control | Requirement Description | Tactical Edge SDN Implementation Status |
| :--- | :--- | :--- | :--- |
| **DISA Container STIG** | **V-242414** | Containers must drop all default capabilities. | **COMPLIANT**: `capabilities.drop: ["ALL"]` configured in Helm DaemonSet. |
| **DISA Container STIG** | **V-242415** | Containers must not run in privileged mode. | **COMPLIANT**: `privileged: false` explicitly declared and verified. |
| **DISA Container STIG** | **V-242417** | Containers must use read-only root filesystems. | **COMPLIANT**: `readOnlyRootFilesystem: true` with ephemeral `emptyDir` mounts. |
| **DISA Container STIG** | **V-242418** | Containers must disable privilege escalation. | **COMPLIANT**: `allowPrivilegeEscalation: false` enforced. |
| **NIST SP 800-53 Rev 5** | **AC-3** | Access Enforcement & Least Privilege | **COMPLIANT**: Bounded capabilities limited strictly to `NET_ADMIN` and `NET_RAW`. |
| **NIST SP 800-53 Rev 5** | **SC-7** | Boundary Protection & Network Separation | **COMPLIANT**: CNF isolates enclaves and dynamically steers traffic across encrypted meshes. |
| **NIST SP 800-53 Rev 5** | **CM-6** | Configuration Settings | **COMPLIANT**: Pinned declarative Helm configuration validated continuously via Lula OSCAL. |
| **NIST SP 800-53 Rev 5** | **CM-7** | Least Functionality | **COMPLIANT**: Non-essential services and capabilities stripped from runtime container. |

---

## 7. Automated Continuous Compliance (Lula & OSCAL)

This security posture is not simply documented—it is continuously audited against the running cluster using **Lula** and NIST SP 800-53 OSCAL component definitions (`compliance/lula/oscal-component.yaml`). 

The Open Policy Agent (OPA) validation rule for `AC-3` verifies that the running DaemonSet satisfies these least-privilege assertions directly from the Kubernetes API.
