"""
Tactical Edge SDN - Standardized Remote Execution and SSH Abstraction Helper.

Provides a unified interface for test harnesses, chaos benchmarks, and integration
suites to execute remote commands across ephemeral lab nodes without hardcoding
usernames, home paths, or brittle nested proxy strings.
"""

import os
import subprocess
import time
from typing import List, Optional, Tuple, Union

# Configurable endpoints with defaults
SHIP_GATEWAY = os.getenv("SHIP_GATEWAY_HOST", "ship-gateway")
SHORE_GATEWAY = os.getenv("SHORE_GATEWAY_HOST", "shore-gateway")
ENCLAVE_CLIENT = os.getenv("ENCLAVE_CLIENT_HOST", "enclave-client")
HYPERVISOR_HOST = os.getenv("HYPERVISOR_HOST", "sandbox-hypervisor-node")

SHORE_IP = os.getenv("SHORE_GATEWAY_IP", "10.200.1.10")
SHORE_PLEO_IP = os.getenv("SHORE_PLEO_IP", "10.100.1.1")
SHORE_MILSAT_IP = os.getenv("SHORE_MILSAT_IP", "10.100.2.1")
SHORE_LOSRF_IP = os.getenv("SHORE_LOSRF_IP", "10.100.3.1")
ENCLAVE_IP = os.getenv("ENCLAVE_IP", "10.10.1.10")

DEFAULT_TIMEOUT = float(os.getenv("SSH_DEFAULT_TIMEOUT", "15.0"))


def get_ssh_options() -> List[str]:
    """Return standard OpenSSH flags for automated non-interactive execution."""
    opts = [
        "-o",
        "BatchMode=yes",
        "-o",
        "ConnectTimeout=5",
        "-o",
        "StrictHostKeyChecking=accept-new",
    ]
    known_hosts = os.path.expanduser("~/.ssh/known_hosts_tactical_lab")
    if os.path.exists(known_hosts):
        opts.extend(["-o", f"UserKnownHostsFile={known_hosts}"])
    else:
        opts.extend(["-o", "UserKnownHostsFile=/dev/null"])
    return opts


def run_cmd(
    cmd: Union[str, List[str]], check: bool = True, timeout: Optional[float] = None
) -> subprocess.CompletedProcess:
    """Execute a local shell or process command with uniform output capture."""
    if isinstance(cmd, str):
        res = subprocess.run(
            cmd,
            shell=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout,
        )
    else:
        res = subprocess.run(
            cmd,
            shell=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout,
        )
    if check and res.returncode != 0:
        raise RuntimeError(
            f"Command failed (exit code {res.returncode}): {cmd}\n" f"Stderr: {res.stderr}\nStdout: {res.stdout}"
        )
    return res


def run_ssh(
    host: str,
    command: str,
    timeout: float = DEFAULT_TIMEOUT,
    check: bool = True,
    retries: int = 1,
    delay: float = 0.5,
) -> subprocess.CompletedProcess:
    """Execute a remote command over SSH with retry on transient network drops."""
    full_cmd = ["ssh"] + get_ssh_options() + [host, command]
    last_res = None
    for attempt in range(retries + 1):
        try:
            res = subprocess.run(
                full_cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=timeout,
            )
            last_res = res
            if res.returncode == 0 or not check:
                return res
        except subprocess.TimeoutExpired as exc:
            if attempt == retries:
                raise RuntimeError(f"SSH command timed out after {timeout}s on {host}: {command}") from exc
        if attempt < retries:
            time.sleep(delay)

    if check and last_res and last_res.returncode != 0:
        raise RuntimeError(
            f"Remote command failed on {host} (exit code {last_res.returncode}): {command}\n"
            f"Stderr: {last_res.stderr}\nStdout: {last_res.stdout}"
        )
    return last_res  # type: ignore


def exec_on_ship(command: str, timeout: float = DEFAULT_TIMEOUT, check: bool = False) -> str:
    """Execute a command on the shipboard gateway / router."""
    res = run_ssh(SHIP_GATEWAY, command, timeout=timeout, check=check)
    return res.stdout.strip()


def exec_on_shore(command: str, timeout: float = DEFAULT_TIMEOUT, check: bool = False) -> str:
    """Execute a command on the shore gateway."""
    res = run_ssh(SHORE_GATEWAY, command, timeout=timeout, check=check)
    return res.stdout.strip()


def exec_on_enclave(command: str, timeout: float = DEFAULT_TIMEOUT, check: bool = False) -> str:
    """Execute a command on the enclave client host."""
    res = run_ssh(ENCLAVE_CLIENT, command, timeout=timeout, check=check)
    return res.stdout.strip()


def probe_enclave_to_shore(
    target_ip: str = SHORE_PLEO_IP, port: int = 8080, timeout: float = 5.0
) -> Tuple[bool, float, str]:
    """
    Probe Shore Gateway from Enclave Client and measure end-to-end latency/status.
    Tries direct connection to ENCLAVE_CLIENT first; if unreachable, bounces via SHIP_GATEWAY.
    """
    curl_cmd = f"curl -s -m {int(timeout)} http://{target_ip}:{port}"
    t0 = time.time()
    res = run_ssh(ENCLAVE_CLIENT, curl_cmd, timeout=timeout + 3.0, check=False)
    elapsed_ms = (time.time() - t0) * 1000.0

    # Fallback via ship router if enclave host is unreachable directly
    if res.returncode != 0 and (
        "No route to host" in res.stderr
        or "timed out" in res.stderr
        or "Connection refused" in res.stderr
        or not res.stdout
    ):
        t0 = time.time()
        proxy_cmd = f"ssh -o BatchMode=yes -o ConnectTimeout=3 {ENCLAVE_CLIENT} '{curl_cmd}'"
        res = run_ssh(SHIP_GATEWAY, proxy_cmd, timeout=timeout + 5.0, check=False)
        elapsed_ms = (time.time() - t0) * 1000.0

    output = (res.stdout or res.stderr).strip()
    success = res.returncode == 0 and ("OPERATIONAL" in output or "SHORE-GATEWAY" in output)
    return success, elapsed_ms, output


def get_router_active_route(host: str = SHIP_GATEWAY) -> Tuple[str, int]:
    """Reads the current lowest metric default route on the router node."""
    out = exec_on_ship("ip route show default")
    lines = out.splitlines()
    if not lines:
        return "none", 9999

    best_dev = "none"
    best_metric = 999999

    for line in lines:
        parts = line.split()
        if "dev" in parts:
            dev_idx = parts.index("dev") + 1
            dev = parts[dev_idx]
            metric = 0
            if "metric" in parts:
                metric_idx = parts.index("metric") + 1
                try:
                    metric = int(parts[metric_idx])
                except ValueError:
                    metric = 0
            if metric < best_metric:
                best_metric = metric
                best_dev = dev

    return best_dev, best_metric
