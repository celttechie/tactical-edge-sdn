#!/usr/bin/env python3
"""
Shipboard Enclave C2 Mission Telemetry Streamer
Generates continuous tactical Cursor-on-Target (CoT) track telemetry and sensor payload streams
routed through the SD-WAN gateway to Shore.
Also exposes an HTTP status endpoint on port 9001 for real-time telemetry querying.
"""

import socket
import time
import json
import threading
import logging
import argparse
from http.server import HTTPServer, BaseHTTPRequestHandler
from dataclasses import dataclass, asdict

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] [enclave-streamer] %(message)s"
)
logger = logging.getLogger("enclave-streamer")

TARGET_HOST = "10.200.1.10"
TARGET_PORT = 9000
STATUS_PORT = 9001

@dataclass
class StreamerStats:
    total_sent: int = 0
    total_bytes_sent: int = 0
    total_acks_received: int = 0
    last_rtt_ms: float = 0.0
    packets_per_sec: float = 0.0
    throughput_kbps: float = 0.0
    target_host: str = TARGET_HOST
    target_port: int = TARGET_PORT
    status: str = "STREAMING"

stats = StreamerStats()
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
    logger.info(f"Enclave Streamer Status HTTP Server listening on port {port}")

def ack_listener(sock):
    global stats
    while True:
        try:
            data, _ = sock.recvfrom(2048)
            now = time.time()
            try:
                msg = json.loads(data.decode("utf-8"))
                echo_seq = msg.get("echo_seq", 0)
                shore_ts = msg.get("shore_ts", now)
                with lock:
                    stats.total_acks_received += 1
            except Exception:
                pass
        except Exception:
            time.sleep(0.1)

def run_streamer(rate_hz: int = 40, payload_size_bytes: int = 512, status_port: int = STATUS_PORT):
    global stats
    start_http_status_server(status_port)

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(0.5)

    # Start background thread to receive downlink ACKs
    t = threading.Thread(target=ack_listener, args=(sock,), daemon=True)
    t.start()

    logger.info(f"Starting Tactical C2 Streamer -> Target: {TARGET_HOST}:{TARGET_PORT} @ {rate_hz} Hz (~{rate_hz * payload_size_bytes * 8 / 1000:.0f} Kbps)")

    interval = 1.0 / float(rate_hz)
    seq = 0
    padding = "X" * max(0, payload_size_bytes - 128)

    last_calc_time = time.time()
    last_calc_pkts = 0
    last_calc_bytes = 0

    while True:
        t0 = time.time()
        seq += 1
        
        telemetry_frame = {
            "type": "TACTICAL_C2_TELEMETRY",
            "seq": seq,
            "timestamp": t0,
            "track_id": "STRIKE-GRP-ALPHA-01",
            "lat": 32.7157 + (seq * 0.0001) % 0.1,
            "lon": -117.1611 + (seq * 0.0001) % 0.1,
            "alt_ft": 25000,
            "payload_pad": padding
        }
        data = json.dumps(telemetry_frame).encode("utf-8")

        try:
            sock.sendto(data, (TARGET_HOST, TARGET_PORT))
            with lock:
                stats.total_sent += 1
                stats.total_bytes_sent += len(data)
        except Exception as e:
            logger.error(f"Send error: {e}")

        # Compute rolling throughput every second
        now = time.time()
        if now - last_calc_time >= 1.0:
            elapsed = now - last_calc_time
            with lock:
                pkts_diff = stats.total_sent - last_calc_pkts
                bytes_diff = stats.total_bytes_sent - last_calc_bytes
                stats.packets_per_sec = round(pkts_diff / elapsed, 1)
                stats.throughput_kbps = round((bytes_diff * 8.0) / (elapsed * 1000.0), 1)
            
            logger.info(
                f"Transmit Stream -> Rate: {stats.packets_per_sec:5.1f} pkts/s | "
                f"Throughput: {stats.throughput_kbps:6.1f} Kbps | "
                f"Total Sent: {stats.total_sent} pkts | Downlink ACKs: {stats.total_acks_received}"
            )
            last_calc_time = now
            last_calc_pkts = stats.total_sent
            last_calc_bytes = stats.total_bytes_sent

        # Sleep remaining time to maintain target rate
        elapsed = time.time() - t0
        sleep_dur = max(0.001, interval - elapsed)
        time.sleep(sleep_dur)

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--rate", type=int, default=40, help="Packet generation rate in Hz")
    parser.add_argument("--size", type=int, default=512, help="Payload size per packet in bytes")
    parser.add_argument("--port", type=int, default=STATUS_PORT, help="Status HTTP server port")
    args = parser.parse_args()
    run_streamer(rate_hz=args.rate, payload_size_bytes=args.size, status_port=args.port)
