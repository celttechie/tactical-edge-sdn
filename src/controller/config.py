"""
SD-WAN Policy Controller Configuration
Defines bearer profiles, SLA thresholds, and dynamic routing weights.
"""

from dataclasses import dataclass, field
from typing import Dict, List

@dataclass
class BearerConfig:
    name: str
    interface: str
    gateway_ip: str
    target_ip: str
    base_metric: int
    expected_latency_ms: float
    max_latency_ms: float = 150.0
    max_loss_pct: float = 5.0
    max_jitter_ms: float = 30.0

@dataclass
class ControllerConfig:
    probe_interval_sec: float = 0.5
    probe_window_size: int = 10
    sla_check_interval_sec: float = 1.0
    degradation_penalty_metric: int = 500
    down_penalty_metric: int = 2000
    enable_frr_bgp: bool = False
    enclave_subnet: str = "10.10.0.0/16"
    shore_subnet: str = "10.200.1.10/32"
    bearers: Dict[str, BearerConfig] = field(default_factory=lambda: {
        "pleops": BearerConfig(
            name="pleops",
            interface="eth-pleops",
            gateway_ip="10.100.1.1",
            target_ip="10.100.1.1",
            base_metric=10,
            expected_latency_ms=40.0,
            max_latency_ms=200.0,
            max_loss_pct=5.0,
            max_jitter_ms=50.0,
        ),
        "milsat": BearerConfig(
            name="milsat",
            interface="eth-milsat",
            gateway_ip="10.100.2.1",
            target_ip="10.100.2.1",
            base_metric=50,
            expected_latency_ms=500.0,
            max_latency_ms=1200.0,
            max_loss_pct=10.0,
            max_jitter_ms=200.0,
        ),
        "losrf": BearerConfig(
            name="losrf",
            interface="eth-losrf",
            gateway_ip="10.100.3.1",
            target_ip="10.100.3.1",
            base_metric=100,
            expected_latency_ms=100.0,
            max_latency_ms=400.0,
            max_loss_pct=10.0,
            max_jitter_ms=100.0,
        ),
    })

DEFAULT_CONFIG = ControllerConfig()
