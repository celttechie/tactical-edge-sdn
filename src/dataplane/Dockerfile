# ==============================================================================
# Tactical Edge SDN Dataplane & Controller Container (CNF)
# Hardened multi-bearer routing engine with FRRouting, WireGuard, and SD-WAN Daemon
# ==============================================================================

FROM debian:12-slim

ENV DEBIAN_FRONTEND=noninteractive

# Install FRRouting, WireGuard, iptables, iproute2, and Python
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    iproute2 \
    iptables \
    conntrack \
    wireguard-tools \
    frr \
    frr-pythontools \
    python3 \
    python3-pip \
    procps \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy FRR configs
COPY src/dataplane/frr/daemons /etc/frr/daemons
COPY src/dataplane/frr/frr.conf /etc/frr/frr.conf
RUN chown -R frr:frr /etc/frr && chmod 640 /etc/frr/*

# Copy application source code and documentation/benchmark data
COPY src/ /app/src/
COPY docs/ /app/docs/
COPY scripts/ /app/scripts/
COPY src/dataplane/entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh && chmod +x /app/scripts/*.sh 2>/dev/null || true

EXPOSE 8080 51820/udp 51821/udp 51822/udp 179

ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["--interval", "0.5", "--check-interval", "1.0"]
