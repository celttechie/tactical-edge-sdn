#!/usr/bin/env python3
"""
Integration Test: Milestone 4 - Automated Continuous Compliance with Lula (OSCAL & NIST SP 800-53)

Validates:
1. OSCAL component definition adheres to OSCAL 1.1.2 schema standards.
2. Lula automated compliance validation passes 100% of defined NIST SP 800-53 Rev 5 controls:
   - Control SC-7: Boundary Protection & Network Separation (DaemonSet active in isolated namespace).
   - Control AC-3: Access Enforcement & Least Privilege Capabilities (NET_ADMIN capability restriction).
   - Control SI-4: Information System Monitoring & Telemetry (Telemetry service on port 8080).
   - Control CM-6: Configuration Settings & Policy Parameters (Multi-bearer SLA config definitions).
"""

import os
import subprocess
import glob
import unittest

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
LULA_DIR = os.path.join(PROJECT_ROOT, "compliance", "lula")
VALIDATIONS_DIR = os.path.join(LULA_DIR, "validations")

class TestLulaOSCALCompliance(unittest.TestCase):
    def test_01_oscal_component_definition_exists(self):
        """Verify OSCAL component definition exists in compliance/lula."""
        oscal_file = os.path.join(LULA_DIR, "oscal-component.yaml")
        self.assertTrue(os.path.exists(oscal_file), "oscal-component.yaml missing")
        with open(oscal_file, "r") as f:
            content = f.read()
            self.assertIn("component-definition", content)
            self.assertIn("tactical-sdn-stack", content)
            self.assertIn("sc-7", content)
            self.assertIn("ac-3", content)
            self.assertIn("si-4", content)
            self.assertIn("cm-6", content)

    def test_02_lula_validation_manifests_lint(self):
        """Verify all individual Lula validation manifests pass schema linting."""
        val_files = glob.glob(os.path.join(VALIDATIONS_DIR, "*.yaml"))
        self.assertGreaterEqual(len(val_files), 4, "Expected at least 4 validation manifests")
        for val_file in val_files:
            res = subprocess.run(
                ["lula", "dev", "lint", "-f", val_file],
                cwd=PROJECT_ROOT,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True
            )
            self.assertEqual(res.returncode, 0, f"Lint failed for {val_file}: {res.stderr}")

    def test_03_lula_live_validations_pass(self):
        """Execute all Lula validations against the live Kubernetes cluster and verify 100% passing results."""
        val_files = glob.glob(os.path.join(VALIDATIONS_DIR, "*.yaml"))
        for val_file in val_files:
            ctrl_name = os.path.basename(val_file).replace(".yaml", "").upper()
            res = subprocess.run(
                ["lula", "dev", "validate", "-f", val_file],
                cwd=PROJECT_ROOT,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True
            )
            print(f" -> Control {ctrl_name} Validation: {'PASSED' if res.returncode == 0 else 'FAILED'}")
            self.assertEqual(res.returncode, 0, f"Validation failed for {val_file}:\nStdout: {res.stdout}\nStderr: {res.stderr}")

    def test_04_lula_full_component_validation_passes(self):
        """Execute full component validation and verify all 4 NIST SP 800-53 controls are satisfied."""
        oscal_file = os.path.join(LULA_DIR, "oscal-component.yaml")
        res = subprocess.run(
            ["lula", "validate", "-f", oscal_file, "--confirm-execution"],
            cwd=PROJECT_ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )
        combined_output = res.stdout + "\n" + res.stderr
        print(f" -> Full OSCAL Component Validation Result:\n{combined_output}")
        self.assertEqual(res.returncode, 0, f"Full component validate failed:\nStdout: {res.stdout}\nStderr: {res.stderr}")
        self.assertNotIn("not-satisfied", combined_output, "Found not-satisfied controls in assessment findings")
        self.assertIn("satisfied", combined_output, "Expected satisfied controls in assessment findings")

        # Verify assessment results file was produced
        results_file = os.path.join(LULA_DIR, "assessment-results.yaml")
        self.assertTrue(os.path.exists(results_file), "assessment-results.yaml was not generated")
        with open(results_file, "r") as f:
            results_content = f.read()
            self.assertIn("assessment-results", results_content)
            self.assertIn("satisfied", results_content)

if __name__ == "__main__":
    print("=" * 75)
    print("TEST: Tactical Edge SDN - Milestone 4: Lula OSCAL Continuous Compliance")
    print("=" * 75)
    unittest.main(verbosity=2)
