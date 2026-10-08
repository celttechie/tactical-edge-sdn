# In-Tree Security Patch Overlays

This directory maintains verified in-tree security patches and build overlays used to remediate upstream CVEs in inherited or third-party dependencies during offline and air-gapped CI/CD builds.

---

## Purpose & Defense Unicorns FDE Pattern

When deploying software into air-gapped defense enclaves (e.g., shipboard CANES or tactical C2 vehicles), Forward Deployed Engineers (FDEs) frequently encounter open CVEs in inherited Government-off-the-shelf (GOTS) baselines or upstream open-source packages (such as FRRouting).

Rather than accepting high-risk vulnerabilities or stalling deployments for 6–18 months awaiting upstream program office patch cycles, the **In-Tree Overlay Pattern** applies minimal, backported, cryptographically verified patches directly during container packaging:

1. **Deterministic Verification**: Every patch file is verified against a pinned SHA-256 cryptographic checksum.
2. **Reproducible Multi-Stage Build**: Patches are applied during Docker/Zarf container build stages using standard unified diffs.
3. **Traceability**: Applied patches are cataloged in generated Software Bills of Materials (SBOMs) and cross-referenced in machine-readable OpenVEX statements (`compliance/sbom/vex-triage.yaml`).

---

## Artifacts in this Directory

* [`CVE-2023-38802-frr-bgpd-attribute-bounds.patch`](file:///home/bjarrett/Projects/tactical-edge-sdn/compliance/patches/CVE-2023-38802-frr-bgpd-attribute-bounds.patch):
  * **Target**: FRRouting `bgpd/bgp_packet.c`
  * **Vulnerability**: BGP UPDATE attribute length out-of-bounds read and crash (DoS)
  * **SHA-256**: `425842b55ae484b8497e288ae2684a03b1ace7908a6adb9161ace624a9222fe1`
* [`apply-overlay-patch.sh`](file:///home/bjarrett/Projects/tactical-edge-sdn/compliance/patches/apply-overlay-patch.sh):
  * Automated runner to verify cryptographic integrity and test/apply overlays.

---

## Usage

### Check / Dry-Run Verification
```bash
./compliance/patches/apply-overlay-patch.sh . check
```

### Apply Patch to Source Tree
```bash
./compliance/patches/apply-overlay-patch.sh /path/to/source apply
```
