"""
SD-WAN Policy Engine
Evaluates live telemetry against tactical SLA constraints, scores bearer health,
and computes dynamic routing metrics.
"""

from dataclasses import dataclass
from enum import Enum
from typing import Dict, List, Optional, Tuple

from .config import BearerConfig, ControllerConfig
from .sla_prober import LinkStats


class LinkHealthState(str, Enum):
    HEALTHY = "HEALTHY"
    DEGRADED = "DEGRADED"
    DOWN = "DOWN"


@dataclass
class BearerEvaluation:
    bearer: str
    state: LinkHealthState
    computed_metric: int
    score: float
    violations: List[str]
    stats: LinkStats


class SDWANPolicyEngine:
    """
    Evaluates real-time SLA metrics for each bearer and computes dynamic routing weights.
    """

    def __init__(self, config: ControllerConfig):
        self.config = config
        self.current_primary: Optional[str] = None
        self.previous_evaluations: Dict[str, BearerEvaluation] = {}

    def evaluate_bearer(self, name: str, stats: LinkStats) -> BearerEvaluation:
        cfg = self.config.bearers.get(name)
        if not cfg:
            raise ValueError(f"Unknown bearer: {name}")

        violations = []
        if not stats.is_alive or stats.packet_loss_pct >= 80.0:
            state = LinkHealthState.DOWN
            computed_metric = cfg.base_metric + self.config.down_penalty_metric
            score = 0.0
            violations.append(f"Link DOWN (Loss: {stats.packet_loss_pct:.1f}%)")
            return BearerEvaluation(
                bearer=name,
                state=state,
                computed_metric=computed_metric,
                score=score,
                violations=violations,
                stats=stats,
            )

        # Check SLA threshold violations
        if stats.latency_ms > cfg.max_latency_ms:
            violations.append(f"Latency {stats.latency_ms:.1f}ms exceeds SLA threshold {cfg.max_latency_ms:.1f}ms")
        if stats.packet_loss_pct > cfg.max_loss_pct:
            violations.append(f"Loss {stats.packet_loss_pct:.1f}% exceeds SLA threshold {cfg.max_loss_pct:.1f}%")
        if stats.jitter_ms > cfg.max_jitter_ms:
            violations.append(f"Jitter {stats.jitter_ms:.1f}ms exceeds SLA threshold {cfg.max_jitter_ms:.1f}ms")

        if violations:
            state = LinkHealthState.DEGRADED
            # Apply degradation penalty metric to demote this bearer
            computed_metric = cfg.base_metric + self.config.degradation_penalty_metric
        else:
            state = LinkHealthState.HEALTHY
            computed_metric = cfg.base_metric

        # Score formulation: lower latency, loss, and jitter -> higher score (0..100)
        norm_latency = max(0.0, 1.0 - (stats.latency_ms / (cfg.max_latency_ms * 2.0)))
        norm_loss = max(0.0, 1.0 - (stats.packet_loss_pct / 100.0))
        norm_jitter = max(0.0, 1.0 - (stats.jitter_ms / (cfg.max_jitter_ms * 2.0)))
        score = (norm_latency * 0.4 + norm_loss * 0.4 + norm_jitter * 0.2) * 100.0

        return BearerEvaluation(
            bearer=name,
            state=state,
            computed_metric=computed_metric,
            score=score,
            violations=violations,
            stats=stats,
        )

    def evaluate_all(self, stats_map: Dict[str, LinkStats]) -> Tuple[Dict[str, BearerEvaluation], bool, Optional[str]]:
        """
        Evaluates all bearers and determines whether a routing mutation is needed.
        Returns: (evaluations, route_change_needed, new_primary_bearer)
        """
        evaluations: Dict[str, BearerEvaluation] = {}
        for name, stats in stats_map.items():
            if name in self.config.bearers:
                evaluations[name] = self.evaluate_bearer(name, stats)

        # Select primary bearer: highest score among healthy, or lowest metric
        sorted_bearers = sorted(
            evaluations.values(),
            key=lambda e: (
                e.state != LinkHealthState.HEALTHY,
                e.computed_metric,
                -e.score,
            ),
        )

        new_primary = sorted_bearers[0].bearer if sorted_bearers else None

        # Check if route change is required
        route_change_needed = False
        if new_primary != self.current_primary:
            route_change_needed = True
            self.current_primary = new_primary
        else:
            # Check if any individual metric changed compared to previous evaluation
            for name, ev in evaluations.items():
                prev = self.previous_evaluations.get(name)
                if prev and prev.computed_metric != ev.computed_metric:
                    route_change_needed = True
                    break

        self.previous_evaluations = evaluations
        return evaluations, route_change_needed, new_primary
