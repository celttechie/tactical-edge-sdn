#!/usr/bin/env python3
"""
Tactical Edge SD-WAN Policy Controller Daemon
Entrypoint for real-time link quality probing, dynamic path steering,
and lightweight Prometheus / Health Telemetry endpoint.
Decoupled from web UI per ADR 0008 (Out-of-Band Management Architecture).
"""

import os
import time
import signal
import sys
import logging
import argparse
import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer, HTTPServer
from typing import Dict, Any, Optional

from .config import ControllerConfig, DEFAULT_CONFIG
from .sla_prober import MultiBearerTelemetryManager
from .policy_engine import SDWANPolicyEngine, LinkHealthState
from .route_actuator import RouteActuator
from .interface_stats import InterfaceStatsCollector


def setup_logging(verbose: bool = False):
    level = logging.DEBUG if verbose else logging.INFO
    logging.basicConfig(
        level=level,
        format="%(asctime)s [%(levelname)s] [%(name)s] %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )


class SDWANTelemetryHTTPHandler(BaseHTTPRequestHandler):
    """
    Lightweight, non-interactive telemetry and health HTTP endpoint for the SD-WAN CNF/router.
    Provides /healthz, /metrics (Prometheus), and /api/status (JSON).
    """

    controller_daemon: Optional["SDWANControllerDaemon"] = None

    def log_message(self, format, *args):
        # Suppress verbose standard HTTP request access logging
        pass

    def do_GET(self):
        if self.path in ("/healthz", "/health"):
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(b'{"status": "UP", "component": "sdwan-controller"}')
        elif self.path in ("/metrics", "/metrics/"):
            metrics_payload = self._generate_prometheus_metrics()
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
            self.end_headers()
            self.wfile.write(metrics_payload.encode("utf-8"))
        elif self.path in ("/api/status", "/api/telemetry"):
            status_data = self._generate_json_status()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps(status_data).encode("utf-8"))
        else:
            self.send_response(404)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(b'{"error": "Not Found"}')

    def _generate_prometheus_metrics(self) -> str:
        daemon = SDWANTelemetryHTTPHandler.controller_daemon
        if not daemon:
            return "# Telemetry daemon unavailable\n"

        lines = [
            "# HELP sdn_controller_up Status of SD-WAN Controller daemon",
            "# TYPE sdn_controller_up gauge",
            "sdn_controller_up 1",
            "",
            "# HELP sdn_bearer_latency_ms Measured RTT latency in milliseconds",
            "# TYPE sdn_bearer_latency_ms gauge",
        ]
        stats = daemon.telemetry.get_all_stats()
        evals = daemon.current_evaluations or {}
        primary = daemon.current_primary or "pleops"

        for b_name, s in stats.items():
            lines.append(f'sdn_bearer_latency_ms{{bearer="{b_name}"}} {s.latency_ms:.2f}')

        lines.extend([
            "",
            "# HELP sdn_bearer_jitter_ms Measured latency jitter in milliseconds",
            "# TYPE sdn_bearer_jitter_ms gauge",
        ])
        for b_name, s in stats.items():
            lines.append(f'sdn_bearer_jitter_ms{{bearer="{b_name}"}} {s.jitter_ms:.2f}')

        lines.extend([
            "",
            "# HELP sdn_bearer_loss_pct Measured packet loss percentage",
            "# TYPE sdn_bearer_loss_pct gauge",
        ])
        for b_name, s in stats.items():
            lines.append(f'sdn_bearer_loss_pct{{bearer="{b_name}"}} {s.packet_loss_pct:.2f}')

        lines.extend([
            "",
            "# HELP sdn_bearer_active Indicates if bearer is currently active primary route (1 or 0)",
            "# TYPE sdn_bearer_active gauge",
        ])
        for b_name in daemon.config.bearers:
            is_active = 1 if b_name == primary else 0
            lines.append(f'sdn_bearer_active{{bearer="{b_name}"}} {is_active}')

        lines.extend([
            "",
            "# HELP sdn_bearer_computed_metric Current computed routing metric applied in kernel",
            "# TYPE sdn_bearer_computed_metric gauge",
        ])
        for b_name, ev in evals.items():
            lines.append(f'sdn_bearer_computed_metric{{bearer="{b_name}"}} {ev.computed_metric}')

        return "\n".join(lines) + "\n"

    def _generate_json_status(self) -> dict:
        daemon = SDWANTelemetryHTTPHandler.controller_daemon
        if not daemon:
            return {"status": "INITIALIZING"}

        stats = daemon.telemetry.get_all_stats()
        evals = daemon.current_evaluations or {}
        primary = daemon.current_primary or "pleops"

        kernel_stats = daemon.interface_collector.update()

        bearers_out = {}
        for b_name, s in stats.items():
            ev = evals.get(b_name)
            iface = daemon.config.bearers[b_name].interface if b_name in daemon.config.bearers else ""
            k_stat = kernel_stats.get(iface)

            rx_kbps = round(k_stat.rx_kbps, 2) if k_stat else 0.0
            tx_kbps = round(k_stat.tx_kbps, 2) if k_stat else 0.0
            throughput_kbps = round(k_stat.throughput_kbps, 2) if k_stat else 0.0
            rx_pps = round(k_stat.rx_pps, 2) if k_stat else 0.0
            tx_pps = round(k_stat.tx_pps, 2) if k_stat else 0.0
            total_dropped = (k_stat.rx_drop + k_stat.tx_drop) if k_stat else 0

            bearers_out[b_name] = {
                "name": b_name,
                "interface": iface,
                "is_active_route": (b_name == primary),
                "state": ev.state.value if ev else ("HEALTHY" if s.is_alive else "DOWN"),
                "latency_ms": round(s.latency_ms, 2),
                "jitter_ms": round(s.jitter_ms, 2),
                "packet_loss_pct": round(s.packet_loss_pct, 2),
                "computed_metric": ev.computed_metric if ev else 100,
                "score": round(ev.score, 2) if ev else 100.0,
                "rx_kbps": rx_kbps,
                "tx_kbps": tx_kbps,
                "throughput_kbps": throughput_kbps,
                "rx_pps": rx_pps,
                "tx_pps": tx_pps,
                "total_dropped": total_dropped,
            }

        return {
            "status": "RUNNING",
            "component": "sdwan-controller",
            "node": "ship-gateway",
            "primary_bearer": primary,
            "bearers": bearers_out,
            "timestamp": time.time(),
        }


class SDWANControllerDaemon:
    def __init__(self, config: ControllerConfig = DEFAULT_CONFIG, telemetry_port: int = 8080):
        self.config = config
        self.telemetry_port = telemetry_port
        self.logger = logging.getLogger("sdwan-controller")

        bearer_dict = {
            name: {
                "interface": cfg.interface,
                "target_ip": cfg.target_ip,
                "gateway_ip": cfg.gateway_ip,
            }
            for name, cfg in config.bearers.items()
        }

        self.telemetry = MultiBearerTelemetryManager(
            bearers=bearer_dict,
            window_size=config.probe_window_size,
            interval=config.probe_interval_sec,
        )
        self.engine = SDWANPolicyEngine(config)
        self.actuator = RouteActuator(config)
        self.interface_collector = InterfaceStatsCollector()
        self._running = False
        self.http_server: Optional[HTTPServer] = None
        self.http_thread: Optional[threading.Thread] = None

        self.current_evaluations: Dict[str, Any] = {}
        self.current_primary: str = "pleops"

    def start(self):
        self._running = True
        self.logger.info("==========================================================")
        self.logger.info("Starting Tactical Edge SD-WAN Policy Controller Daemon")
        self.logger.info(f"Monitoring Bearers: {list(self.config.bearers.keys())}")
        self.logger.info(
            f"Probe Interval: {self.config.probe_interval_sec}s | Window Size: {self.config.probe_window_size}"
        )
        self.logger.info(f"Telemetry & Prometheus endpoint listening on port: {self.telemetry_port}")
        self.logger.info("==========================================================")

        self.telemetry.start()
        self._start_telemetry_server()

        signal.signal(signal.SIGINT, self._handle_signal)
        signal.signal(signal.SIGTERM, self._handle_signal)

        try:
            while self._running:
                time.sleep(self.config.sla_check_interval_sec)
                self.tick()
        except KeyboardInterrupt:
            self.stop()

    def _start_telemetry_server(self):
        try:
            SDWANTelemetryHTTPHandler.controller_daemon = self
            self.http_server = ThreadingHTTPServer(("0.0.0.0", self.telemetry_port), SDWANTelemetryHTTPHandler)
            self.http_thread = threading.Thread(target=self.http_server.serve_forever, daemon=True)
            self.http_thread.start()
            self.logger.info(f"SD-WAN Prometheus /metrics endpoint active at http://0.0.0.0:{self.telemetry_port}/metrics")
        except Exception as e:
            self.logger.error(f"Failed to start telemetry endpoint server: {e}")

    def _handle_signal(self, signum, frame):
        self.logger.info(f"Received signal {signum}, initiating graceful shutdown...")
        self.stop()

    def stop(self):
        self._running = False
        self.telemetry.stop()
        if self.http_server:
            self.http_server.shutdown()
        self.logger.info("SD-WAN Policy Controller stopped.")

    def tick(self):
        """Single control loop tick: read telemetry, evaluate policy, apply mutations."""
        stats_map = self.telemetry.get_all_stats()
        evaluations, route_change_needed, new_primary = self.engine.evaluate_all(stats_map)

        self.current_evaluations = evaluations
        self.current_primary = new_primary

        for name, ev in evaluations.items():
            s = ev.stats
            status_symbol = (
                "✓"
                if ev.state == LinkHealthState.HEALTHY
                else ("⚠" if ev.state == LinkHealthState.DEGRADED else "✗")
            )
            self.logger.info(
                f"[{status_symbol}] {name:7s} | State: {ev.state.value:8s} | "
                f"RTT: {s.latency_ms:6.1f}ms | Jitter: {s.jitter_ms:4.1f}ms | Loss: {s.packet_loss_pct:5.1f}% | "
                f"Metric: {ev.computed_metric:4d} | Score: {ev.score:5.1f}"
            )

        if route_change_needed:
            self.logger.warning(
                f"*** ROUTING CHANGE TRIGGERED: New Optimal Primary Bearer -> [{new_primary.upper()}] ***"
            )
            self.actuator.apply_routing_table(evaluations)


def main():
    parser = argparse.ArgumentParser(description="Tactical Edge SD-WAN Policy Controller Daemon")
    parser.add_argument("-v", "--verbose", action="store_true", help="Enable verbose debug logging")
    parser.add_argument("--interval", type=float, default=0.5, help="Probe interval in seconds")
    parser.add_argument("--check-interval", type=float, default=1.0, help="SLA check interval in seconds")
    parser.add_argument("--port", type=int, default=8080, help="Telemetry HTTP /metrics port")
    args = parser.parse_args()

    setup_logging(args.verbose)
    cfg = DEFAULT_CONFIG
    cfg.probe_interval_sec = args.interval
    cfg.sla_check_interval_sec = args.check_interval

    daemon = SDWANControllerDaemon(cfg, telemetry_port=args.port)
    daemon.start()


if __name__ == "__main__":
    main()
