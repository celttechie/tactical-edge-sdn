"""
Route Actuator
Applies dynamic route mutations to the Linux Kernel routing table and FRR control plane
based on Policy Engine evaluations.
"""

import subprocess
import logging
from typing import Dict, List, Optional
from .config import ControllerConfig
from .policy_engine import BearerEvaluation, LinkHealthState

logger = logging.getLogger("sdwan-actuator")

class RouteActuator:
    """
    Manages Linux kernel and FRR routing state dynamically.
    """
    def __init__(self, config: ControllerConfig):
        self.config = config

    def _exec(self, cmd: str) -> subprocess.CompletedProcess:
        logger.debug(f"Executing: {cmd}")
        return subprocess.run(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

    def apply_routing_table(self, evaluations: Dict[str, BearerEvaluation]) -> bool:
        """
        Applies updated metric weights to Linux kernel routing tables.
        Ensures traffic to shore_subnet and default destination flows via optimal bearer.
        """
        success = True
        logger.info("==> Applying dynamic route mutation across active bearers...")

        for name, ev in evaluations.items():
            cfg = self.config.bearers.get(name)
            if not cfg:
                continue

            metric = ev.computed_metric
            ifname = cfg.interface
            gw = cfg.gateway_ip

            # 1. Purge existing routes for this interface to ensure clean metric assignment
            for target in ["default", self.config.shore_subnet]:
                out = self._exec(f"ip route show {target} dev {ifname}").stdout.strip()
                for line in out.splitlines():
                    if line.strip():
                        # line is e.g. "default via 10.100.1.1 metric 10" or "10.200.1.0/24 via 10.100.1.1 metric 10"
                        self._exec(f"ip route del {line.strip()} dev {ifname} 2>/dev/null || true")

            # 2. Add route to destination shore subnet with updated metric
            cmd_shore = f"ip route add {self.config.shore_subnet} via {gw} dev {ifname} metric {metric}"
            res1 = self._exec(cmd_shore)
            if res1.returncode != 0:
                logger.error(f"Failed to update route for {name} ({cmd_shore}): {res1.stderr.strip()}")
                success = False

            # 3. Add default route with updated metric
            cmd_default = f"ip route add default via {gw} dev {ifname} metric {metric}"
            res2 = self._exec(cmd_default)
            if res2.returncode != 0:
                logger.error(f"Failed to update default route for {name} ({cmd_default}): {res2.stderr.strip()}")
                success = False

            logger.info(f" -> Bearer {name:7s} ({ifname:10s} -> {gw}) Metric set to {metric:4d} [State: {ev.state.value}]")

        # Flush conntrack table if link is completely DOWN to accelerate TCP re-routing
        for name, ev in evaluations.items():
            cfg = self.config.bearers.get(name)
            if cfg and ev.state == LinkHealthState.DOWN:
                self._exec(f"conntrack -D -o {cfg.interface} 2>/dev/null || true")

        return success

    def sync_frr_bgp_metric(self, bearer: str, local_pref: int) -> bool:
        """
        Optional: Mutates BGP route-map local preference via FRR vtysh for BGP-managed overlays.
        """
        vtysh_cmd = f"vtysh -c 'conf t' -c 'route-map RM_{bearer.upper()}_IN permit 10' -c 'set local-preference {local_pref}' -c 'exit'"
        res = self._exec(vtysh_cmd)
        return res.returncode == 0
