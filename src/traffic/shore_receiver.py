#!/usr/bin/env python3
"""
Shore Gateway Tactical Ingest Receiver & Downlink C2 Tasker
Listens for continuous C2 mission telemetry and sensor streams from the shipboard enclave,
records packet arrival statistics, and echoes downlink command acknowledgments.
Also exposes an HTTP status endpoint on port 9001 for real-time telemetry querying.
"""

import argparse
import json
import logging
import socket
import threading
import time
from dataclasses import asdict, dataclass
from http.server import BaseHTTPRequestHandler, HTTPServer

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] [shore-ingest] %(message)s")
logger = logging.getLogger("shore-ingest")

LISTEN_HOST = "0.0.0.0"
LISTEN_PORT = 9000
STATUS_PORT = 9001


@dataclass
class IngestStats:
    total_packets_received: int = 0
    total_bytes_received: int = 0
    packets_per_sec: float = 0.0
    throughput_kbps: float = 0.0
    last_seq: int = 0
    sequence_gaps: int = 0
    last_packet_ts: float = 0.0
    status: str = "INGESTING"


stats = IngestStats()
lock = threading.Lock()


class StatsHTTPHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path in ("/status", "/metrics", "/"):
            with lock:
                payload = asdict(stats)
            data = json.dumps(payload).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        pass  # Suppress normal access logs


def start_http_status_server(port: int = STATUS_PORT):
    server = HTTPServer(("0.0.0.0", port), StatsHTTPHandler)
    t = threading.Thread(target=server.serve_forever, daemon=True)
    t.start()
    logger.info(f"Shore Receiver Status HTTP Server listening on port {port}")


def udp_receiver_loop(listen_port: int = LISTEN_PORT, status_port: int = STATUS_PORT):
    start_http_status_server(status_port)

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind((LISTEN_HOST, listen_port))
    logger.info(f"Tactical Shore Ingest Receiver listening on UDP {LISTEN_HOST}:{listen_port}")

    last_calc_time = time.time()
    last_calc_pkts = 0
    last_calc_bytes = 0

    while True:
        try:
            data, addr = sock.recvfrom(2048)
            now = time.time()
            with lock:
                stats.total_packets_received += 1
                stats.total_bytes_received += len(data)
                stats.last_packet_ts = now

                # Parse JSON telemetry payload if valid
                try:
                    payload = json.loads(data.decode("utf-8"))
                    seq = payload.get("seq", 0)
                    if stats.last_seq > 0 and seq > stats.last_seq + 1:
                        stats.sequence_gaps += seq - stats.last_seq - 1
                    stats.last_seq = seq
                except Exception:
                    pass

            # Calculate rolling rates every 1.0s
            if now - last_calc_time >= 1.0:
                elapsed = now - last_calc_time
                with lock:
                    pkts_diff = stats.total_packets_received - last_calc_pkts
                    bytes_diff = stats.total_bytes_received - last_calc_bytes
                    stats.packets_per_sec = round(pkts_diff / elapsed, 1)
                    stats.throughput_kbps = round((bytes_diff * 8.0) / (elapsed * 1000.0), 1)

                logger.info(
                    f"Ingest Stream -> Rate: {stats.packets_per_sec:5.1f} pkts/s | "
                    f"Throughput: {stats.throughput_kbps:6.1f} Kbps | "
                    f"Total: {stats.total_packets_received} pkts | Gaps: {stats.sequence_gaps}"
                )
                last_calc_time = now
                last_calc_pkts = stats.total_packets_received
                last_calc_bytes = stats.total_bytes_received

            # Echo downlink command ACK periodically
            if stats.total_packets_received % 10 == 0:
                ack_payload = json.dumps(
                    {
                        "type": "DOWNLINK_C2_ACK",
                        "echo_seq": stats.last_seq,
                        "shore_ts": time.time(),
                    }
                ).encode("utf-8")
                sock.sendto(ack_payload, addr)

        except Exception as e:
            logger.error(f"Error in ingest loop: {e}")
            time.sleep(0.1)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=LISTEN_PORT, help="UDP listening port")
    parser.add_argument("--status-port", type=int, default=STATUS_PORT, help="Status HTTP server port")
    args = parser.parse_args()
    udp_receiver_loop(listen_port=args.port, status_port=args.status_port)
