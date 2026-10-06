/**
 * Tactical Edge SD-WAN // Operations HUD & Chaos Controller Logic
 * Real-Time Telemetry Streaming, Animated Topology Canvas, & Multi-Bearer Charts
 */

// Global State
let latestState = null;
let eventSource = null;
let chartHistory = {
    timestamps: [],
    pleops: [],
    milsat: [],
    losrf: []
};
const MAX_CHART_POINTS = 45;

// Packet Flow Animation State
const particles = [];
const MAX_PARTICLES = 18;

// Topology Node Positions (Normalized or Pixel coordinates)
const topoNodes = {
    enclave: { x: 100, y: 130, label: "USS ENCLAVE\n10.10.1.10", icon: "⚓" },
    router:  { x: 340, y: 130, label: "SD-WAN CNF\n10.200.1.2", icon: "🔀" },
    pleops:  { x: 620, y: 50,  label: "P-LEO SATCOM\n10.100.1.1", icon: "🛰️", key: "pleops" },
    milsat:  { x: 620, y: 130, label: "MILSATCOM GEO\n10.100.2.1", icon: "🛰️", key: "milsat" },
    losrf:   { x: 620, y: 210, label: "TACTICAL LOS-RF\n10.100.3.1", icon: "📡", key: "losrf" },
    shore:   { x: 960, y: 130, label: "SHORE C2 HUB\n10.200.1.10", icon: "🏛️" }
};

// Zulu Time Updater
function updateZuluTime() {
    const now = new Date();
    const zulu = now.toISOString().substring(11, 19) + "Z";
    const el = document.getElementById("zulu-clock");
    if (el) el.innerText = zulu;
}
setInterval(updateZuluTime, 1000);
updateZuluTime();

// Particle Generation & Movement
function updateParticles(primaryBearer) {
    // Spawn new particle periodically
    if (particles.length < MAX_PARTICLES && Math.random() < 0.35) {
        particles.push({
            segment: 0, // 0: Enclave->Router, 1: Router->Bearer, 2: Bearer->Shore
            progress: 0.0,
            speed: 0.015 + Math.random() * 0.008,
            bearer: primaryBearer || "pleops",
            size: 3.5 + Math.random() * 2
        });
    }

    // Advance particles
    for (let i = particles.length - 1; i >= 0; i--) {
        const p = particles[i];
        p.progress += p.speed;
        if (p.progress >= 1.0) {
            p.progress = 0.0;
            p.segment++;
            if (p.segment > 2) {
                particles.splice(i, 1);
            }
        }
    }
}

// Draw Animated Topology Canvas
function drawTopology() {
    const canvas = document.getElementById("topology-canvas");
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    const width = canvas.width;
    const height = canvas.height;

    ctx.clearRect(0, 0, width, height);

    // Draw Subtle Grid Background
    ctx.strokeStyle = "rgba(30, 41, 59, 0.4)";
    ctx.lineWidth = 1;
    for (let x = 0; x < width; x += 40) {
        ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, height); ctx.stroke();
    }
    for (let y = 0; y < height; y += 40) {
        ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(width, y); ctx.stroke();
    }

    const primaryBearer = latestState ? latestState.primary_bearer : "pleops";
    const bearersData = latestState ? latestState.bearers : {};

    // 1. Draw Ingress Link (Enclave -> Router)
    ctx.beginPath();
    ctx.moveTo(topoNodes.enclave.x, topoNodes.enclave.y);
    ctx.lineTo(topoNodes.router.x, topoNodes.router.y);
    ctx.strokeStyle = "rgba(0, 229, 255, 0.6)";
    ctx.lineWidth = 3;
    ctx.stroke();

    // 2. Draw Bearer Links (Router -> Bearer -> Shore)
    const bearerKeys = ["pleops", "milsat", "losrf"];
    bearerKeys.forEach(key => {
        const node = topoNodes[key];
        const bInfo = bearersData ? bearersData[key] : null;
        const isActive = (key === primaryBearer);
        const readiness = bInfo ? bInfo.readiness : "FMC";

        let linkColor = "rgba(100, 116, 139, 0.4)";
        let linkWidth = 2;

        if (readiness === "NMC") {
            linkColor = "rgba(255, 51, 68, 0.8)";
            linkWidth = 3;
        } else if (readiness === "PMC") {
            linkColor = isActive ? "rgba(255, 184, 0, 0.9)" : "rgba(255, 184, 0, 0.4)";
            linkWidth = isActive ? 4 : 2;
        } else if (isActive) {
            linkColor = "rgba(0, 255, 102, 0.95)";
            linkWidth = 4;
        }

        // Line: Router -> Bearer
        ctx.beginPath();
        ctx.moveTo(topoNodes.router.x, topoNodes.router.y);
        ctx.lineTo(node.x, node.y);
        ctx.strokeStyle = linkColor;
        ctx.lineWidth = linkWidth;
        if (readiness === "NMC") {
            ctx.setLineDash([6, 6]);
        } else {
            ctx.setLineDash([]);
        }
        ctx.stroke();

        // Line: Bearer -> Shore
        ctx.beginPath();
        ctx.moveTo(node.x, node.y);
        ctx.lineTo(topoNodes.shore.x, topoNodes.shore.y);
        ctx.strokeStyle = linkColor;
        ctx.lineWidth = linkWidth;
        ctx.stroke();
        ctx.setLineDash([]);

        // If Link has Chaos/Severe impairment, draw warning pulse
        if (readiness === "NMC" || (bInfo && bInfo.chaos_state && bInfo.chaos_state.includes("BLACKOUT"))) {
            ctx.fillStyle = "rgba(255, 51, 68, 0.3)";
            ctx.beginPath();
            ctx.arc(node.x, node.y, 35, 0, Math.PI * 2);
            ctx.fill();
            
            // Draw Warning X
            ctx.strokeStyle = "#ff3344";
            ctx.lineWidth = 3;
            ctx.beginPath();
            ctx.moveTo(node.x - 12, node.y - 12); ctx.lineTo(node.x + 12, node.y + 12);
            ctx.moveTo(node.x + 12, node.y - 12); ctx.lineTo(node.x - 12, node.y + 12);
            ctx.stroke();
        }
    });

    // 3. Draw Moving Packets / Particles
    updateParticles(primaryBearer);
    particles.forEach(p => {
        let pX = 0, pY = 0;
        const bNode = topoNodes[p.bearer] || topoNodes.pleops;

        if (p.segment === 0) {
            // Enclave -> Router
            pX = topoNodes.enclave.x + (topoNodes.router.x - topoNodes.enclave.x) * p.progress;
            pY = topoNodes.enclave.y + (topoNodes.router.y - topoNodes.enclave.y) * p.progress;
        } else if (p.segment === 1) {
            // Router -> Bearer
            pX = topoNodes.router.x + (bNode.x - topoNodes.router.x) * p.progress;
            pY = topoNodes.router.y + (bNode.y - topoNodes.router.y) * p.progress;
        } else if (p.segment === 2) {
            // Bearer -> Shore
            pX = bNode.x + (topoNodes.shore.x - bNode.x) * p.progress;
            pY = bNode.y + (topoNodes.shore.y - bNode.y) * p.progress;
        }

        // Particle Glow
        const particleColor = p.bearer === "pleops" ? "#00ff66" :
                              p.bearer === "milsat" ? "#ffb800" :
                              p.bearer === "losrf"  ? "#00e5ff" : "#00ffff";
        ctx.shadowBlur = 10;
        ctx.shadowColor = particleColor;
        ctx.fillStyle = particleColor;
        ctx.beginPath();
        ctx.arc(pX, pY, p.size, 0, Math.PI * 2);
        ctx.fill();
        ctx.shadowBlur = 0; // Reset
    });

    // 4. Draw Nodes
    Object.keys(topoNodes).forEach(nodeKey => {
        const node = topoNodes[nodeKey];
        const isActive = (nodeKey === primaryBearer || nodeKey === "enclave" || nodeKey === "router" || nodeKey === "shore");
        
        // Node Box
        ctx.fillStyle = "#151d2a";
        ctx.strokeStyle = isActive ? "#00e5ff" : "#334155";
        ctx.lineWidth = 2;
        
        ctx.beginPath();
        ctx.roundRect(node.x - 45, node.y - 25, 90, 50, 6);
        ctx.fill();
        ctx.stroke();

        // Icon
        ctx.font = "16px sans-serif";
        ctx.textAlign = "center";
        ctx.fillText(node.icon, node.x, node.y - 4);

        // Labels
        ctx.fillStyle = "#e2e8f0";
        ctx.font = "9px 'Share Tech Mono', monospace";
        const lines = node.label.split("\n");
        ctx.fillText(lines[0], node.x, node.y + 12);
        ctx.fillStyle = "#64748b";
        ctx.fillText(lines[1], node.x, node.y + 21);
    });

    requestAnimationFrame(drawTopology);
}

// Real-Time Throughput Timeline Chart (Canvas)
function drawThroughputChart() {
    const canvas = document.getElementById("throughput-chart");
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    const width = canvas.width;
    const height = canvas.height;

    ctx.clearRect(0, 0, width, height);

    // Padding
    const padL = 40, padR = 20, padT = 15, padB = 25;
    const chartW = width - padL - padR;
    const chartH = height - padT - padB;

    // Grid lines & Y Axis (0 - 500 Kbps)
    ctx.strokeStyle = "rgba(30, 41, 59, 0.6)";
    ctx.lineWidth = 1;
    ctx.fillStyle = "#64748b";
    ctx.font = "9px 'Share Tech Mono', monospace";
    ctx.textAlign = "right";

    const ySteps = [0, 100, 200, 300, 400, 500];
    const maxVal = 500;

    ySteps.forEach(val => {
        const y = padT + chartH - (val / maxVal) * chartH;
        ctx.beginPath();
        ctx.moveTo(padL, y);
        ctx.lineTo(width - padR, y);
        ctx.stroke();
        ctx.fillText(val + "k", padL - 6, y + 3);
    });

    if (chartHistory.timestamps.length < 2) return;

    // Draw Line Series for each bearer
    const series = [
        { key: "pleops", color: "#00ff66", data: chartHistory.pleops },
        { key: "milsat", color: "#ffb800", data: chartHistory.milsat },
        { key: "losrf",  color: "#00e5ff", data: chartHistory.losrf }
    ];

    const count = chartHistory.timestamps.length;
    const stepX = chartW / (MAX_CHART_POINTS - 1);

    series.forEach(s => {
        ctx.strokeStyle = s.color;
        ctx.lineWidth = 2.5;
        ctx.beginPath();

        s.data.forEach((val, idx) => {
            const x = padL + idx * stepX;
            const clampedVal = Math.min(maxVal, Math.max(0, val));
            const y = padT + chartH - (clampedVal / maxVal) * chartH;
            if (idx === 0) {
                ctx.moveTo(x, y);
            } else {
                ctx.lineTo(x, y);
            }
        });
        ctx.stroke();
    });
}

// Update UI Components with Live Telemetry State
function renderState(state) {
    latestState = state;

    // 1. Overall Mission Readiness Badge
    const readEl = document.getElementById("overall-readiness");
    if (readEl) {
        readEl.className = "status-value " + (
            state.overall_readiness === "FMC" ? "badge-fmc" :
            state.overall_readiness === "PMC" ? "badge-pmc" : "badge-nmc"
        );
        readEl.innerText = state.overall_readiness === "FMC" ? "FMC (OPERATIONAL)" :
                           state.overall_readiness === "PMC" ? "PMC (DEGRADED)" : "NMC (NON-CAPABLE)";
    }

    // 2. Active Primary Route Header
    const routeEl = document.getElementById("header-primary-route");
    if (routeEl) {
        const nameMap = { pleops: "P-LEO SATCOM", milsat: "MILSATCOM GEO", losrf: "TACTICAL LOS-RF" };
        routeEl.innerText = nameMap[state.primary_bearer] || state.primary_bearer.toUpperCase();
    }

    // 3. Traffic Stream Pill
    if (state.enclave_traffic) {
        const ppsEl = document.getElementById("top-enclave-rate");
        const kbpsEl = document.getElementById("top-enclave-kbps");
        if (ppsEl) ppsEl.innerText = (state.enclave_traffic.packets_per_sec || 40.0).toFixed(1) + " pkts/s";
        if (kbpsEl) kbpsEl.innerText = (state.enclave_traffic.throughput_kbps || 220.0).toFixed(1) + " Kbps";
    }

    // 4. Update Bearer Cards
    const bData = state.bearers || {};
    ["pleops", "milsat", "losrf"].forEach(key => {
        const b = bData[key];
        if (!b) return;

        const card = document.getElementById(`card-${key}`);
        if (card) {
            if (b.is_active_route) {
                card.classList.add("active-route-card");
            } else {
                card.classList.remove("active-route-card");
            }
        }

        const rBadge = document.getElementById(`${key}-route-badge`);
        if (rBadge) {
            rBadge.className = "route-badge " + (b.is_active_route ? "active-badge" : "standby-badge");
            rBadge.innerText = b.is_active_route ? "PRIMARY" : "STANDBY";
        }

        const readBadge = document.getElementById(`${key}-readiness`);
        if (readBadge) {
            readBadge.className = "readiness-badge " + (
                b.readiness === "FMC" ? "badge-fmc" :
                b.readiness === "PMC" ? "badge-pmc" : "badge-nmc"
            );
            readBadge.innerText = b.readiness;
        }

        const latEl = document.getElementById(`${key}-latency`);
        if (latEl) latEl.innerHTML = `${b.latency_ms.toFixed(1)} <span class="unit">ms</span>`;

        const jitEl = document.getElementById(`${key}-jitter`);
        if (jitEl) jitEl.innerHTML = `${b.jitter_ms.toFixed(1)} <span class="unit">ms</span>`;

        const lossEl = document.getElementById(`${key}-loss`);
        if (lossEl) lossEl.innerHTML = `${b.packet_loss_pct.toFixed(1)} <span class="unit">%</span>`;

        const scoreEl = document.getElementById(`${key}-score`);
        if (scoreEl) scoreEl.innerText = b.score.toFixed(1);

        const tpEl = document.getElementById(`${key}-throughput`);
        if (tpEl) tpEl.innerHTML = `${b.throughput_kbps.toFixed(1)} <span class="unit">Kbps</span>`;

        const dropEl = document.getElementById(`${key}-drops`);
        if (dropEl) dropEl.innerText = b.total_dropped;

        const chaosPill = document.getElementById(`${key}-chaos-pill`);
        if (chaosPill) {
            chaosPill.innerText = `STATUS: ${b.chaos_state || 'NORMAL'}`;
            if (b.chaos_state && b.chaos_state.includes("BLACKOUT")) {
                chaosPill.style.color = "#ff3344";
            } else if (b.chaos_state && b.chaos_state.includes("DEGRADED")) {
                chaosPill.style.color = "#ffb800";
            } else {
                chaosPill.style.color = "#64748b";
            }
        }
    });

    // 5. Append Chart Point
    const pKbps = bData.pleops ? bData.pleops.throughput_kbps : 0;
    const mKbps = bData.milsat ? bData.milsat.throughput_kbps : 0;
    const lKbps = bData.losrf ? bData.losrf.throughput_kbps : 0;

    chartHistory.timestamps.push(new Date().toLocaleTimeString());
    chartHistory.pleops.push(pKbps);
    chartHistory.milsat.push(mKbps);
    chartHistory.losrf.push(lKbps);

    if (chartHistory.timestamps.length > MAX_CHART_POINTS) {
        chartHistory.timestamps.shift();
        chartHistory.pleops.shift();
        chartHistory.milsat.shift();
        chartHistory.losrf.shift();
    }
    drawThroughputChart();

    // 6. Update Event Log
    if (state.recent_events && state.recent_events.length > 0) {
        const terminal = document.getElementById("events-terminal");
        const countBadge = document.getElementById("event-count");
        if (countBadge) countBadge.innerText = `${state.recent_events.length} EVENTS`;

        if (terminal) {
            terminal.innerHTML = "";
            state.recent_events.forEach(evt => {
                const entry = document.createElement("div");
                const sevClass = evt.severity === "DANGER" ? "event-danger" :
                                 evt.severity === "WARNING" ? "event-warning" :
                                 evt.severity === "SUCCESS" ? "event-success" : "event-info";
                entry.className = `event-entry ${sevClass}`;
                entry.innerHTML = `
                    <span class="event-time">[${evt.time_str || ''}]</span>
                    <span class="event-tag">[${evt.type}]</span>
                    <span class="event-msg">${evt.message}</span>
                `;
                terminal.appendChild(entry);
            });
        }
    }
}

// Connect to Server-Sent Events (SSE) Stream
function startSSE() {
    const sseIndicator = document.getElementById("sse-indicator");
    const sseStatus = document.getElementById("sse-status-text");

    if (eventSource) {
        eventSource.close();
    }

    eventSource = new EventSource("/api/stream");

    eventSource.onopen = () => {
        if (sseIndicator) sseIndicator.className = "live-dot pulse-green";
        if (sseStatus) sseStatus.innerText = "LIVE TELEMETRY (2Hz)";
    };

    eventSource.onmessage = (event) => {
        try {
            const data = JSON.parse(event.data);
            renderState(data);
        } catch (err) {
            console.error("Error parsing telemetry frame:", err);
        }
    };

    eventSource.onerror = () => {
        if (sseIndicator) sseIndicator.className = "live-dot";
        if (sseStatus) sseStatus.innerText = "RECONNECTING...";
        // Fallback polling
        setTimeout(pollStatus, 1000);
    };
}

// Fallback Polling Function
async function pollStatus() {
    try {
        const resp = await fetch("/api/status");
        if (resp.ok) {
            const data = await resp.json();
            renderState(data);
        }
    } catch (err) {
        console.warn("Poll failed:", err);
    }
}

// Interactive Chaos Trigger
async function triggerChaos(action, target = "") {
    console.log(`Triggering Chaos Action: ${action}`);
    try {
        const resp = await fetch("/api/chaos", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ action: action, target: target })
        });
        const result = await resp.json();
        console.log("Chaos Action Result:", result);
        // Force immediate refresh
        pollStatus();
    } catch (err) {
        console.error("Failed to inject chaos:", err);
    }
}

// Initialization on Page Load
window.addEventListener("DOMContentLoaded", () => {
    // Initial draw
    requestAnimationFrame(drawTopology);
    drawThroughputChart();

    // Start SSE Telemetry
    startSSE();
});
