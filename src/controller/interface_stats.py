#!/usr/bin/env python3
"""
Linux Kernel Network Interface Statistics Scraper
Scrapes /proc/net/dev and /sys/class/net to calculate rolling throughput (Kbps),
packet rates (pps), and dropped packet counts per bearer interface.
"""

import os
import re
import time
from dataclasses import asdict, dataclass
from typing import Dict, Optional, Tuple


@dataclass
class InterfaceMetric:
    interface: str
    rx_bytes: int = 0
    tx_bytes: int = 0
    rx_packets: int = 0
    tx_packets: int = 0
    rx_drop: int = 0
    tx_drop: int = 0
    rx_errs: int = 0
    tx_errs: int = 0
    rx_kbps: float = 0.0
    tx_kbps: float = 0.0
    throughput_kbps: float = 0.0
    rx_pps: float = 0.0
    tx_pps: float = 0.0
    timestamp: float = 0.0


class InterfaceStatsCollector:
    """Scrapes /proc/net/dev directly on the host or router."""

    def __init__(self, interfaces: Optional[list] = None):
        self.interfaces = interfaces or [
            "eth-pleops",
            "eth-milsat",
            "eth-losrf",
            "eth-unclass",
            "eth-mgmt",
        ]
        self.prev_stats: Dict[str, Tuple[int, int, int, int, int, int, float]] = {}
        self.current_metrics: Dict[str, InterfaceMetric] = {}

    def parse_proc_net_dev(self, content: Optional[str] = None) -> Dict[str, dict]:
        """Parse raw /proc/net/dev contents."""
        if content is None:
            if not os.path.exists("/proc/net/dev"):
                return {}
            try:
                with open("/proc/net/dev", "r") as f:
                    content = f.read()
            except Exception:
                return {}

        results = {}
        lines = content.strip().splitlines()
        for line in lines[2:]:  # Skip the header lines
            if ":" not in line:
                continue
            iface, data = line.split(":", 1)
            iface = iface.strip()
            fields = data.split()
            if len(fields) >= 16:
                # Fields:
                # RX: bytes(0), packets(1), errs(2), drop(3), fifo(4), frame(5), compressed(6), multicast(7)
                # TX: bytes(8), packets(9), errs(10), drop(11), fifo(12), colls(13), carrier(14), compressed(15)
                results[iface] = {
                    "rx_bytes": int(fields[0]),
                    "rx_packets": int(fields[1]),
                    "rx_errs": int(fields[2]),
                    "rx_drop": int(fields[3]),
                    "tx_bytes": int(fields[8]),
                    "tx_packets": int(fields[9]),
                    "tx_errs": int(fields[10]),
                    "tx_drop": int(fields[11]),
                }
        return results

    def update(self, raw_proc_content: Optional[str] = None) -> Dict[str, InterfaceMetric]:
        """Update interface metrics and compute rolling rates."""
        now = time.time()
        raw_stats = self.parse_proc_net_dev(raw_proc_content)

        for iface in self.interfaces:
            stats = raw_stats.get(iface)
            if not stats:
                continue

            rx_bytes = stats["rx_bytes"]
            tx_bytes = stats["tx_bytes"]
            rx_pkts = stats["rx_packets"]
            tx_pkts = stats["tx_packets"]
            rx_drop = stats["rx_drop"]
            tx_drop = stats["tx_drop"]
            rx_errs = stats["rx_errs"]
            tx_errs = stats["tx_errs"]

            rx_kbps = 0.0
            tx_kbps = 0.0
            rx_pps = 0.0
            tx_pps = 0.0

            if iface in self.prev_stats:
                p_rxb, p_txb, p_rxp, p_txp, p_rxd, p_txd, p_time = self.prev_stats[iface]
                elapsed = max(0.001, now - p_time)

                # Compute deltas
                rx_bytes_delta = max(0, rx_bytes - p_rxb)
                tx_bytes_delta = max(0, tx_bytes - p_txb)
                rx_pkts_delta = max(0, rx_pkts - p_rxp)
                tx_pkts_delta = max(0, tx_pkts - p_txp)

                rx_kbps = (rx_bytes_delta * 8.0) / (elapsed * 1000.0)
                tx_kbps = (tx_bytes_delta * 8.0) / (elapsed * 1000.0)
                rx_pps = rx_pkts_delta / elapsed
                tx_pps = tx_pkts_delta / elapsed

            self.prev_stats[iface] = (
                rx_bytes,
                tx_bytes,
                rx_pkts,
                tx_pkts,
                rx_drop,
                tx_drop,
                now,
            )

            metric = InterfaceMetric(
                interface=iface,
                rx_bytes=rx_bytes,
                tx_bytes=tx_bytes,
                rx_packets=rx_pkts,
                tx_packets=tx_pkts,
                rx_drop=rx_drop,
                tx_drop=tx_drop,
                rx_errs=rx_errs,
                tx_errs=tx_errs,
                rx_kbps=round(rx_kbps, 2),
                tx_kbps=round(tx_kbps, 2),
                throughput_kbps=round(rx_kbps + tx_kbps, 2),
                rx_pps=round(rx_pps, 1),
                tx_pps=round(tx_pps, 1),
                timestamp=now,
            )
            self.current_metrics[iface] = metric

        return self.current_metrics


if __name__ == "__main__":
    collector = InterfaceStatsCollector()
    print("Collecting interface statistics (Ctrl+C to stop)...")
    try:
        while True:
            metrics = collector.update()
            for iface, m in metrics.items():
                print(
                    f"[{iface:12s}] RX: {m.rx_kbps:7.2f} Kbps ({m.rx_pps:5.1f} pps) | TX: {m.tx_kbps:7.2f} Kbps ({m.tx_pps:5.1f} pps) | Drops: RX={m.rx_drop} TX={m.tx_drop}"
                )
            time.sleep(1.0)
    except KeyboardInterrupt:
        pass
