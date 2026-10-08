"""
SLA Prober Engine
Performs continuous link-quality sampling (latency, jitter, and loss percentage)
across tactical bearer interfaces.
"""

import select
import socket
import struct
import subprocess
import threading
import time
from collections import deque
from dataclasses import dataclass
from typing import Dict, Optional, Tuple


@dataclass
class LinkStats:
    bearer: str
    target_ip: str
    is_alive: bool
    latency_ms: float
    jitter_ms: float
    packet_loss_pct: float
    total_probes_sent: int
    total_probes_lost: int
    last_update_ts: float


class BearerSLAProber:
    """
    Continuous active link prober for a single bearer.
    Uses socket ICMP / UDP echo ping or HTTP probes to evaluate bearer metrics.
    """

    def __init__(
        self,
        name: str,
        target_ip: str,
        interface: str,
        window_size: int = 10,
        timeout: float = 2.0,
    ):
        self.name = name
        self.target_ip = target_ip
        self.interface = interface
        self.window_size = window_size
        self.timeout = timeout

        self.samples: deque = deque(maxlen=window_size)
        self.seq = 0
        self.total_sent = 0
        self.total_lost = 0
        self._lock = threading.Lock()
        self._last_rtt = None

    def probe_once(self) -> Tuple[bool, Optional[float]]:
        """
        Executes a single probe to target_ip via interface.
        Tries TCP port 8080 telemetry probe, falling back to ICMP ping.
        """
        self.seq += 1
        self.total_sent += 1
        t0 = time.time()

        # Test TCP/HTTP port 8080 probe to shore gateway
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(self.timeout)
            sock.connect((self.target_ip, 8080))
            req = b"GET / HTTP/1.1\r\nHost: probe\r\nConnection: close\r\n\r\n"
            sock.sendall(req)
            sock.recv(64)
            sock.close()
            rtt_ms = (time.time() - t0) * 1000.0
            return True, rtt_ms
        except Exception:
            pass

        # Fallback to ICMP ping bound to interface
        try:
            res = subprocess.run(
                [
                    "ping",
                    "-c",
                    "1",
                    "-W",
                    str(int(self.timeout)),
                    "-I",
                    self.interface,
                    self.target_ip,
                ],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=self.timeout + 0.2,
            )
            if res.returncode == 0:
                # Parse rtt from ping output: rtt min/avg/max/mdev = 40.123/...
                for line in res.stdout.splitlines():
                    if "rtt min/avg/max/mdev" in line or "round-trip" in line:
                        parts = line.split("=")[1].strip().split("/")
                        return True, float(parts[1])
                rtt_ms = (time.time() - t0) * 1000.0
                return True, rtt_ms
        except Exception:
            pass

        self.total_lost += 1
        return False, None

    def record_sample(self, success: bool, rtt_ms: Optional[float]):
        with self._lock:
            self.samples.append((success, rtt_ms))

    def compute_stats(self) -> LinkStats:
        with self._lock:
            if not self.samples:
                return LinkStats(
                    bearer=self.name,
                    target_ip=self.target_ip,
                    is_alive=False,
                    latency_ms=9999.0,
                    jitter_ms=999.0,
                    packet_loss_pct=100.0,
                    total_probes_sent=self.total_sent,
                    total_probes_lost=self.total_lost,
                    last_update_ts=time.time(),
                )

            total_window = len(self.samples)
            successful_rtts = [rtt for success, rtt in self.samples if success and rtt is not None]
            lost_count = total_window - len(successful_rtts)
            loss_pct = (lost_count / total_window) * 100.0

            if not successful_rtts:
                return LinkStats(
                    bearer=self.name,
                    target_ip=self.target_ip,
                    is_alive=False,
                    latency_ms=9999.0,
                    jitter_ms=999.0,
                    packet_loss_pct=100.0,
                    total_probes_sent=self.total_sent,
                    total_probes_lost=self.total_lost,
                    last_update_ts=time.time(),
                )

            avg_latency = sum(successful_rtts) / len(successful_rtts)

            # Jitter calculation: mean absolute difference between successive RTTs
            if len(successful_rtts) > 1:
                jitters = [abs(successful_rtts[i] - successful_rtts[i - 1]) for i in range(1, len(successful_rtts))]
                avg_jitter = sum(jitters) / len(jitters)
            else:
                avg_jitter = 0.0

            is_alive = loss_pct < 80.0

            return LinkStats(
                bearer=self.name,
                target_ip=self.target_ip,
                is_alive=is_alive,
                latency_ms=avg_latency,
                jitter_ms=avg_jitter,
                packet_loss_pct=loss_pct,
                total_probes_sent=self.total_sent,
                total_probes_lost=self.total_lost,
                last_update_ts=time.time(),
            )


class MultiBearerTelemetryManager:
    """Manages concurrent SLA probing threads across all active bearers."""

    def __init__(self, bearers: Dict[str, dict], window_size: int = 10, interval: float = 0.5):
        self.interval = interval
        self.probers: Dict[str, BearerSLAProber] = {}
        for name, cfg in bearers.items():
            self.probers[name] = BearerSLAProber(
                name=name,
                target_ip=cfg["target_ip"],
                interface=cfg["interface"],
                window_size=window_size,
            )
        self._running = False
        self._threads: list = []

    def _worker(self, prober: BearerSLAProber):
        while self._running:
            success, rtt = prober.probe_once()
            prober.record_sample(success, rtt)
            time.sleep(self.interval)

    def start(self):
        self._running = True
        for prober in self.probers.values():
            t = threading.Thread(target=self._worker, args=(prober,), daemon=True)
            t.start()
            self._threads.append(t)

    def stop(self):
        self._running = False

    def get_all_stats(self) -> Dict[str, LinkStats]:
        return {name: prober.compute_stats() for name, prober in self.probers.items()}
