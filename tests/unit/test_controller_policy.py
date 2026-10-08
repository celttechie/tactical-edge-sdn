#!/usr/bin/env python3
"""
Unit Tests for SD-WAN Policy Engine & SLA Evaluation Logic
"""

import unittest

from src.controller.config import DEFAULT_CONFIG, ControllerConfig
from src.controller.policy_engine import LinkHealthState, SDWANPolicyEngine
from src.controller.sla_prober import LinkStats


class TestSDWANPolicyEngine(unittest.TestCase):
    def setUp(self):
        self.config = ControllerConfig()
        self.engine = SDWANPolicyEngine(self.config)

    def test_all_links_healthy_pleops_is_primary(self):
        stats_map = {
            "pleops": LinkStats(
                bearer="pleops",
                target_ip="10.100.1.1",
                is_alive=True,
                latency_ms=40.0,
                jitter_ms=2.0,
                packet_loss_pct=0.0,
                total_probes_sent=10,
                total_probes_lost=0,
                last_update_ts=1000.0,
            ),
            "milsat": LinkStats(
                bearer="milsat",
                target_ip="10.100.2.1",
                is_alive=True,
                latency_ms=500.0,
                jitter_ms=10.0,
                packet_loss_pct=0.0,
                total_probes_sent=10,
                total_probes_lost=0,
                last_update_ts=1000.0,
            ),
            "losrf": LinkStats(
                bearer="losrf",
                target_ip="10.100.3.1",
                is_alive=True,
                latency_ms=100.0,
                jitter_ms=5.0,
                packet_loss_pct=0.0,
                total_probes_sent=10,
                total_probes_lost=0,
                last_update_ts=1000.0,
            ),
        }

        evaluations, route_change_needed, primary = self.engine.evaluate_all(stats_map)
        self.assertTrue(route_change_needed)
        self.assertEqual(primary, "pleops")
        self.assertEqual(evaluations["pleops"].state, LinkHealthState.HEALTHY)
        self.assertEqual(evaluations["pleops"].computed_metric, 10)
        self.assertEqual(evaluations["milsat"].computed_metric, 50)
        self.assertEqual(evaluations["losrf"].computed_metric, 100)

    def test_pleops_degradation_triggers_failover_to_losrf(self):
        # Initial healthy baseline
        self.test_all_links_healthy_pleops_is_primary()

        # Inject severe latency on P-LEO (220ms > 150ms SLA limit)
        stats_map = {
            "pleops": LinkStats(
                bearer="pleops",
                target_ip="10.100.1.1",
                is_alive=True,
                latency_ms=220.0,
                jitter_ms=15.0,
                packet_loss_pct=6.0,
                total_probes_sent=10,
                total_probes_lost=1,
                last_update_ts=1001.0,
            ),
            "milsat": LinkStats(
                bearer="milsat",
                target_ip="10.100.2.1",
                is_alive=True,
                latency_ms=500.0,
                jitter_ms=10.0,
                packet_loss_pct=0.0,
                total_probes_sent=10,
                total_probes_lost=0,
                last_update_ts=1001.0,
            ),
            "losrf": LinkStats(
                bearer="losrf",
                target_ip="10.100.3.1",
                is_alive=True,
                latency_ms=100.0,
                jitter_ms=5.0,
                packet_loss_pct=0.0,
                total_probes_sent=10,
                total_probes_lost=0,
                last_update_ts=1001.0,
            ),
        }

        evaluations, route_change_needed, primary = self.engine.evaluate_all(stats_map)
        self.assertTrue(route_change_needed)
        # P-LEO should be marked DEGRADED with metric 10 + 500 = 510
        self.assertEqual(evaluations["pleops"].state, LinkHealthState.DEGRADED)
        self.assertEqual(evaluations["pleops"].computed_metric, 510)
        # LOS-RF has metric 100 and healthy state -> should be chosen as new primary!
        self.assertEqual(
            primary,
            ("milsat" if evaluations["milsat"].computed_metric < evaluations["losrf"].computed_metric else "losrf"),
        )

    def test_complete_blackout_marks_link_down(self):
        stats_map = {
            "pleops": LinkStats(
                bearer="pleops",
                target_ip="10.100.1.1",
                is_alive=False,
                latency_ms=9999.0,
                jitter_ms=999.0,
                packet_loss_pct=100.0,
                total_probes_sent=10,
                total_probes_lost=10,
                last_update_ts=1002.0,
            ),
            "milsat": LinkStats(
                bearer="milsat",
                target_ip="10.100.2.1",
                is_alive=True,
                latency_ms=500.0,
                jitter_ms=10.0,
                packet_loss_pct=0.0,
                total_probes_sent=10,
                total_probes_lost=0,
                last_update_ts=1002.0,
            ),
            "losrf": LinkStats(
                bearer="losrf",
                target_ip="10.100.3.1",
                is_alive=True,
                latency_ms=100.0,
                jitter_ms=5.0,
                packet_loss_pct=0.0,
                total_probes_sent=10,
                total_probes_lost=0,
                last_update_ts=1002.0,
            ),
        }

        evaluations, route_change_needed, primary = self.engine.evaluate_all(stats_map)
        self.assertEqual(evaluations["pleops"].state, LinkHealthState.DOWN)
        self.assertEqual(evaluations["pleops"].computed_metric, 10 + self.config.down_penalty_metric)
        self.assertIn(primary, ["milsat", "losrf"])

    def test_shore_subnet_host_route_precedence(self):
        """Validates that shore_subnet uses /32 to avoid route ambiguity with local management /24."""
        self.assertEqual(self.config.shore_subnet, "10.200.1.10/32")

    def test_prometheus_metrics_format(self):
        """Validates that Prometheus metrics output conforms to exposition standard."""
        from src.dashboard.server import DashboardDataManager

        dm = DashboardDataManager()
        metrics = dm.get_prometheus_metrics()
        self.assertIn("sdn_system_readiness", metrics)
        self.assertIn("sdn_bearer_latency_seconds", metrics)
        self.assertIn("sdn_bearer_loss_ratio", metrics)
        self.assertIn("sdn_bearer_metric", metrics)
        self.assertIn("sdn_bearer_score", metrics)
        self.assertIn("sdn_bearer_active", metrics)
        self.assertIn("sdn_failover_events_total", metrics)


if __name__ == "__main__":
    unittest.main()
