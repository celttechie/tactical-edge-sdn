#!/usr/bin/env python3
"""
Unit Tests for tests.common.ssh Remote Execution & SSH Abstraction Helper.
"""

import os
import unittest
from unittest.mock import MagicMock, patch

from tests.common import ssh


class TestSSHCommon(unittest.TestCase):
    def test_default_hosts_and_ips(self):
        """Verify default host aliases and IP assignments."""
        self.assertEqual(ssh.SHIP_GATEWAY, "ship-gateway")
        self.assertEqual(ssh.SHORE_GATEWAY, "shore-gateway")
        self.assertEqual(ssh.ENCLAVE_CLIENT, "enclave-client")
        self.assertEqual(ssh.HYPERVISOR_HOST, "sandbox-hypervisor-node")
        self.assertEqual(ssh.SHORE_IP, "10.200.1.10")
        self.assertEqual(ssh.SHORE_PLEO_IP, "10.100.1.1")

    def test_ssh_options_construction(self):
        """Verify standard OpenSSH options include batch mode and connect timeout."""
        opts = ssh.get_ssh_options()
        self.assertIn("-o", opts)
        self.assertIn("BatchMode=yes", opts)
        self.assertIn("ConnectTimeout=5", opts)
        self.assertIn("StrictHostKeyChecking=accept-new", opts)

    @patch("subprocess.run")
    def test_run_ssh_success(self, mock_run):
        """Verify successful remote SSH invocation."""
        mock_res = MagicMock()
        mock_res.returncode = 0
        mock_res.stdout = "hello ship"
        mock_res.stderr = ""
        mock_run.return_value = mock_res

        res = ssh.run_ssh("ship-gateway", "echo hello")
        self.assertEqual(res.returncode, 0)
        self.assertEqual(res.stdout, "hello ship")
        mock_run.assert_called_once()

    @patch("tests.common.ssh.run_ssh")
    def test_exec_on_ship(self, mock_run_ssh):
        """Verify exec_on_ship calls run_ssh with SHIP_GATEWAY."""
        mock_res = MagicMock()
        mock_res.stdout = "eth-pleops 10\n"
        mock_run_ssh.return_value = mock_res

        out = ssh.exec_on_ship("ip route")
        self.assertEqual(out, "eth-pleops 10")
        mock_run_ssh.assert_called_once_with("ship-gateway", "ip route", timeout=ssh.DEFAULT_TIMEOUT, check=False)

    @patch("tests.common.ssh.exec_on_ship")
    def test_get_router_active_route_parsing(self, mock_exec):
        """Verify parsing of lowest metric default route."""
        mock_exec.return_value = (
            "default via 10.100.2.1 dev eth-milsat metric 50\n"
            "default via 10.100.1.1 dev eth-pleops metric 10\n"
            "default via 10.100.3.1 dev eth-losrf metric 100\n"
        )
        dev, metric = ssh.get_router_active_route()
        self.assertEqual(dev, "eth-pleops")
        self.assertEqual(metric, 10)

    @patch("tests.common.ssh.run_ssh")
    def test_probe_enclave_to_shore_success(self, mock_run_ssh):
        """Verify probe_enclave_to_shore reports success when OPERATIONAL returned."""
        mock_res = MagicMock()
        mock_res.returncode = 0
        mock_res.stdout = "OPERATIONAL HTTP/1.1 200 OK"
        mock_res.stderr = ""
        mock_run_ssh.return_value = mock_res

        success, latency, output = ssh.probe_enclave_to_shore("10.100.1.1")
        self.assertTrue(success)
        self.assertIn("OPERATIONAL", output)
        self.assertGreaterEqual(latency, 0.0)


if __name__ == "__main__":
    unittest.main()
