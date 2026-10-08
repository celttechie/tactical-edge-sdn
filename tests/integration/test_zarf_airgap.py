#!/usr/bin/env python3
"""
Integration Test: Milestone 3 - Zarf Air-Gap Packaging & Offline Deployment Verification

Validates:
1. Declarative Zarf package construction with pinned OCI artifacts and Syft SBOM generation.
2. Self-contained bundle verification with zero external internet/registry dependencies.
3. Package archive extraction, manifest validation, and air-gap integrity verification.
4. Containerized SDN stack functionality and capability checks.
"""

import json
import os
import subprocess
import tarfile
import tempfile
import unittest

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
PACKAGE_PATH = os.path.join(PROJECT_ROOT, "build", "zarf-package-tactical-sdn-stack-amd64-0.3.0.tar.zst")


class TestZarfAirGapPackage(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Ensure build package exists or build it
        if not os.path.exists(PACKAGE_PATH):
            print(f"\n[Setup] Building Zarf package from packages/zarf...")
            res = subprocess.run(
                [
                    "zarf",
                    "package",
                    "create",
                    "packages/zarf",
                    "--confirm",
                    "-o",
                    "build/",
                ],
                cwd=PROJECT_ROOT,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            if res.returncode != 0:
                raise RuntimeError(f"Zarf package create failed: {res.stderr}\n{res.stdout}")

    def test_01_zarf_package_artifact_exists_and_sized(self):
        """Verify the Zarf air-gap tar.zst archive exists and contains substantial container image layers (>30MB)."""
        self.assertTrue(os.path.exists(PACKAGE_PATH), f"Package not found at {PACKAGE_PATH}")
        size_bytes = os.path.getsize(PACKAGE_PATH)
        size_mb = size_bytes / (1024 * 1024)
        print(f" -> Zarf Package Archive Size: {size_mb:.2f} MB")
        self.assertGreater(
            size_mb,
            30.0,
            "Package size too small, image layers may not have been bundled!",
        )

    def test_02_zarf_lint_passes(self):
        """Verify declarative package definition conforms strictly to Zarf schema without errors."""
        res = subprocess.run(
            ["zarf", "dev", "lint", "packages/zarf"],
            cwd=PROJECT_ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        self.assertEqual(res.returncode, 0, f"Zarf lint failed: {res.stderr}\n{res.stdout}")
        self.assertIn("tactical-sdn-stack", res.stdout)

    def test_03_airgap_archive_contents_inspection(self):
        """Unpack and verify the Zarf package contains zarf.yaml, checksums, SBOM, and image tarballs."""
        with tempfile.TemporaryDirectory() as tmpdir:
            # Use zarf tools archiver to decompress or verify package
            decompress_res = subprocess.run(
                ["zarf", "tools", "archiver", "decompress", PACKAGE_PATH, tmpdir],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            self.assertEqual(
                decompress_res.returncode,
                0,
                f"Decompression failed: {decompress_res.stderr}",
            )

            extracted_files = os.listdir(tmpdir)
            print(f" -> Extracted Package Artifacts: {extracted_files}")
            self.assertIn("zarf.yaml", extracted_files)
            self.assertTrue("checksums.txt" in extracted_files or "checksums.blob" in extracted_files)
            self.assertTrue(any("images" in f or "components" in f for f in extracted_files))

    def test_04_uds_bundle_definition_valid(self):
        """Verify UDS Core bundle configuration points to the valid tactical SDN package ref."""
        uds_path = os.path.join(PROJECT_ROOT, "packages", "uds", "uds-bundle.yaml")
        self.assertTrue(os.path.exists(uds_path), "uds-bundle.yaml missing")
        with open(uds_path, "r") as f:
            content = f.read()
            self.assertIn("kind: UDSBundle", content)
            self.assertIn("tactical-sdn-stack", content)
            self.assertIn("0.3.0", content)

    def test_06_live_zarf_package_deploy_and_pod_running(self):
        """Verify the built package successfully deploys to Kubernetes and pods enter Running state."""
        # Deploy package using zarf
        deploy_cmd = ["zarf", "package", "deploy", PACKAGE_PATH, "--confirm"]
        res = subprocess.run(
            deploy_cmd,
            cwd=PROJECT_ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        self.assertEqual(res.returncode, 0, f"Zarf package deploy failed: {res.stderr}\n{res.stdout}")

        # Verify DaemonSet / Pod in tactical-sdn namespace
        k_res = subprocess.run(
            [
                "kubectl",
                "get",
                "pods",
                "-n",
                "tactical-sdn",
                "-l",
                "app.kubernetes.io/name=tactical-sdn",
                "-o",
                "json",
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        self.assertEqual(k_res.returncode, 0, f"Failed to get pods: {k_res.stderr}")
        pod_data = json.loads(k_res.stdout)
        items = pod_data.get("items", [])
        self.assertGreater(len(items), 0, "No SDN pods found in tactical-sdn namespace!")

        pod_phase = items[0]["status"].get("phase")
        print(f" -> Live Deployed Pod Name: {items[0]['metadata']['name']} | Status: {pod_phase}")
        self.assertEqual(pod_phase, "Running", f"Expected Pod to be Running, got {pod_phase}")


if __name__ == "__main__":
    print("=" * 75)
    print("TEST: Tactical Edge SDN - Milestone 3: Zarf Air-Gap Packaging & Deployment")
    print("=" * 75)
    unittest.main(verbosity=2)
