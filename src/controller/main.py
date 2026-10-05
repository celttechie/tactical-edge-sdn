#!/usr/bin/env python3
"""
Tactical Edge SD-WAN Policy Controller Daemon
Entrypoint for real-time link quality probing and dynamic path steering.
"""

import time
import signal
import sys
import logging
import argparse
import json
from .config import ControllerConfig, DEFAULT_CONFIG
from .sla_prober import MultiBearerTelemetryManager
from .policy_engine import SDWANPolicyEngine, LinkHealthState
from .route_actuator import RouteActuator

def setup_logging(verbose: bool = False):
    level = logging.DEBUG if verbose else logging.INFO
    logging.basicConfig(
        level=level,
        format="%(asctime)s [%(levelname)s] [%(name)s] %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S"
    )

class SDWANControllerDaemon:
    def __init__(self, config: ControllerConfig = DEFAULT_CONFIG):
        self.config = config
        self.logger = logging.getLogger("sdwan-controller")
        
        bearer_dict = {
            name: {
                "interface": cfg.interface,
                "target_ip": cfg.target_ip,
                "gateway_ip": cfg.gateway_ip
            }
            for name, cfg in config.bearers.items()
        }
        
        self.telemetry = MultiBearerTelemetryManager(
            bearers=bearer_dict,
            window_size=config.probe_window_size,
            interval=config.probe_interval_sec
        )
        self.engine = SDWANPolicyEngine(config)
        self.actuator = RouteActuator(config)
        self._running = False

    def start(self):
        self._running = True
        self.logger.info("==========================================================")
        self.logger.info("Starting Tactical Edge SD-WAN Policy Controller Daemon")
        self.logger.info(f"Monitoring Bearers: {list(self.config.bearers.keys())}")
        self.logger.info(f"Probe Interval: {self.config.probe_interval_sec}s | Window Size: {self.config.probe_window_size}")
        self.logger.info("==========================================================")

        self.telemetry.start()

        # Handle termination signals
        signal.signal(signal.SIGINT, self._handle_signal)
        signal.signal(signal.SIGTERM, self._handle_signal)

        try:
            while self._running:
                time.sleep(self.config.sla_check_interval_sec)
                self.tick()
        except KeyboardInterrupt:
            self.stop()

    def _handle_signal(self, signum, frame):
        self.logger.info(f"Received signal {signum}, initiating graceful shutdown...")
        self.stop()

    def stop(self):
        self._running = False
        self.telemetry.stop()
        self.logger.info("SD-WAN Policy Controller stopped.")

    def tick(self):
        """Single control loop tick: read telemetry, evaluate policy, apply mutations."""
        stats_map = self.telemetry.get_all_stats()
        evaluations, route_change_needed, new_primary = self.engine.evaluate_all(stats_map)

        # Log link metrics snapshot
        for name, ev in evaluations.items():
            s = ev.stats
            status_symbol = "✓" if ev.state == LinkHealthState.HEALTHY else ("⚠" if ev.state == LinkHealthState.DEGRADED else "✗")
            self.logger.info(
                f"[{status_symbol}] {name:7s} | State: {ev.state.value:8s} | "
                f"RTT: {s.latency_ms:6.1f}ms | Jitter: {s.jitter_ms:4.1f}ms | Loss: {s.packet_loss_pct:5.1f}% | "
                f"Metric: {ev.computed_metric:4d} | Score: {ev.score:5.1f}"
            )

        if route_change_needed:
            self.logger.warning(f"*** ROUTING CHANGE TRIGGERED: New Optimal Primary Bearer -> [{new_primary.upper()}] ***")
            self.actuator.apply_routing_table(evaluations)

def main():
    parser = argparse.ArgumentParser(description="Tactical Edge SD-WAN Policy Controller Daemon")
    parser.add_argument("-v", "--verbose", action="store_true", help="Enable verbose debug logging")
    parser.add_argument("--interval", type=float, default=0.5, help="Probe interval in seconds")
    parser.add_argument("--check-interval", type=float, default=1.0, help="SLA check interval in seconds")
    args = parser.parse_args()

    setup_logging(args.verbose)
    cfg = DEFAULT_CONFIG
    cfg.probe_interval_sec = args.interval
    cfg.sla_check_interval_sec = args.check_interval

    daemon = SDWANControllerDaemon(cfg)
    daemon.start()

if __name__ == "__main__":
    main()
