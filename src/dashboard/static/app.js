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

// HUD Toast System & Event Tracking
const seenEventKeys = new Set();
let isInitialStateLoad = true;

function showHUDToast(severity, tag, message) {
    const container = document.getElementById("hud-toast-container");
    if (!container) return;

    const toast = document.createElement("div");
    const sevClass = severity === "DANGER" ? "toast-danger" :
                     severity === "WARNING" ? "toast-warning" :
                     severity === "SUCCESS" ? "toast-success" : "toast-info";
    const icon = severity === "DANGER" ? "🚨" :
                 severity === "WARNING" ? "⚠" :
                 severity === "SUCCESS" ? "✓" : "ℹ️";

    toast.className = `hud-toast ${sevClass}`;
    toast.innerHTML = `
        <span class="toast-icon">${icon}</span>
        <div class="toast-content">
            <strong>[${tag}]</strong> ${message}
        </div>
    `;
    container.appendChild(toast);

    setTimeout(() => {
        toast.style.opacity = "0";
        toast.style.transform = "translateX(50px)";
        setTimeout(() => toast.remove(), 400);
    }, 4500);
}

// Reactive Chaos Active Status Card inside Drawer
function updateChaosStatusCard(chaosState) {
    const card = document.getElementById("chaos-active-card");
    const dot = document.getElementById("chaos-indicator-dot");
    const title = document.getElementById("chaos-status-title");
    const desc = document.getElementById("chaos-status-desc");
    if (!card || !title || !desc) return;

    if (!chaosState) return;
    const pleopsState = chaosState.pleops || "NORMAL";
    const milsatState = chaosState.milsat || "NORMAL";
    const losrfState = chaosState.losrf || "NORMAL";

    if (pleopsState.includes("BLACKOUT") || pleopsState.includes("100PCT")) {
        card.className = "chaos-active-card status-jammed";
        if (dot) dot.className = "chaos-status-indicator pulse-red";
        title.innerText = "🚨 ACTIVE: EW RF JAMMING ATTACK";
        desc.innerText = "P-LEO link severed (100% loss). Dynamic SLA failover to alternate bearer.";
    } else if (milsatState.includes("RAIN_FADE") || milsatState.includes("DEGRADED")) {
        card.className = "chaos-active-card status-degraded";
        if (dot) dot.className = "chaos-status-indicator pulse-yellow";
        title.innerText = "🌧️ ACTIVE: SATELLITE RAIN FADE";
        desc.innerText = "350ms delay + 15% packet loss on MILSAT GEO link.";
    } else if (losrfState.includes("JAMMING") || losrfState.includes("DEGRADED")) {
        card.className = "chaos-active-card status-degraded";
        if (dot) dot.className = "chaos-status-indicator pulse-yellow";
        title.innerText = "📡 ACTIVE: RF MULTIPATH INTERFERENCE";
        desc.innerText = "150ms delay + 20% packet loss on Tactical LOS-RF link.";
    } else if (pleopsState === "FLAPPING") {
        card.className = "chaos-active-card status-degraded";
        if (dot) dot.className = "chaos-status-indicator pulse-yellow";
        title.innerText = "🔄 ACTIVE: LINK FLAPPING SIMULATOR";
        desc.innerText = "Rapid 2s on/off link cycle triggering route damping hysteresis.";
    } else {
        card.className = "chaos-active-card";
        if (dot) dot.className = "chaos-status-indicator pulse-green";
        title.innerText = "BASELINE: ALL BEARERS HEALTHY";
        desc.innerText = "No active impairments. Dynamic SLA path steering operational.";
    }
}


// Particle Generation & Movement
function getBearerPacketSpeed(bearerKey) {
    if (!latestState || !latestState.bearers) {
        return bearerKey === "milsat" ? 0.010 : 0.020;
    }
    const bInfo = latestState.bearers[bearerKey];
    const latency = bInfo && bInfo.latency_ms ? bInfo.latency_ms : (bearerKey === "milsat" ? 500 : 40);
    if (latency > 300) return 0.009 + Math.random() * 0.003; // High-latency GEO MILSAT
    if (latency > 100) return 0.014 + Math.random() * 0.004; // Moderate latency
    return 0.022 + Math.random() * 0.004; // Low-latency LEO / Tactical LOS-RF
}

function updateParticles(primaryBearer) {
    const activeBearer = primaryBearer || "pleops";

    // Spawn new particle periodically from USS Enclave
    if (particles.length < MAX_PARTICLES && Math.random() < 0.35) {
        particles.push({
            segment: 0, // 0: Enclave->Router, 1: Router->Bearer, 2: Bearer->Shore
            progress: 0.0,
            speed: 0.020 + Math.random() * 0.004, // Ingress link speed
            bearer: activeBearer,
            size: 3.5 + Math.random() * 2
        });
    }

    const bearersData = latestState ? latestState.bearers : {};

    // Advance particles
    for (let i = particles.length - 1; i >= 0; i--) {
        const p = particles[i];
        p.progress += p.speed;
        if (p.progress >= 1.0) {
            p.progress = 0.0;
            p.segment++;

            if (p.segment === 1) {
                // When departing Router, steer along current active primary bearer
                p.bearer = activeBearer;
                p.speed = getBearerPacketSpeed(p.bearer);
                const bInfo = bearersData ? bearersData[p.bearer] : null;
                p.severed = bInfo && (
                    bInfo.readiness === "NMC" ||
                    bInfo.packet_loss_pct >= 90 ||
                    (bInfo.chaos_state && bInfo.chaos_state.includes("BLACKOUT"))
                );
            } else if (p.segment === 2) {
                // Check if bearer dropped the packet (e.g. 100% loss / EW Jamming / NMC)
                const bInfo = bearersData ? bearersData[p.bearer] : null;
                const isSevered = p.severed || (bInfo && (
                    bInfo.readiness === "NMC" ||
                    bInfo.packet_loss_pct >= 90 ||
                    (bInfo.chaos_state && bInfo.chaos_state.includes("BLACKOUT"))
                ));
                if (isSevered) {
                    // Packet severed at jammed bearer; drop it before Shore
                    particles.splice(i, 1);
                    continue;
                }
            } else if (p.segment > 2) {
                // Reached Shore C2 Hub
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

        // If Link has Chaos/Severe impairment, draw warning pulse and 100% loss badge
        if (readiness === "NMC" || (bInfo && (bInfo.packet_loss_pct >= 90 || (bInfo.chaos_state && bInfo.chaos_state.includes("BLACKOUT"))))) {
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

            // Draw "100% PACKET LOSS" pill above node
            ctx.fillStyle = "#ff3344";
            ctx.font = "bold 9px 'Share Tech Mono', monospace";
            ctx.textAlign = "center";
            ctx.fillText("⚠️ 100% LOSS (DROPPING)", node.x, node.y - 32);
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
        const isSev = p.severed || (p.segment >= 1 && bearersData && bearersData[p.bearer] && (
            bearersData[p.bearer].readiness === "NMC" ||
            bearersData[p.bearer].packet_loss_pct >= 90 ||
            (bearersData[p.bearer].chaos_state && bearersData[p.bearer].chaos_state.includes("BLACKOUT"))
        ));
        const particleColor = isSev ? "#ff3344" :
                              p.bearer === "pleops" ? "#00ff66" :
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
    const isLegacyGateway = latestState && latestState.modernization && latestState.modernization.gateway_type === "LEGACY_VNF";
    if (isLegacyGateway) {
        topoNodes.router.label = "LEGACY ROUTER\n10.200.1.2 (VNF)";
        topoNodes.router.icon = "📟";
    } else {
        topoNodes.router.label = "SD-WAN CNF\n10.200.1.2 (K3s)";
        topoNodes.router.icon = "🔀";
    }

    Object.keys(topoNodes).forEach(nodeKey => {
        const node = topoNodes[nodeKey];
        const isActive = (nodeKey === primaryBearer || nodeKey === "enclave" || nodeKey === "router" || nodeKey === "shore");
        
        // Node Box
        ctx.fillStyle = (nodeKey === "router" && isLegacyGateway) ? "#20171a" : "#151d2a";
        const strokeColor = (nodeKey === "router" && isLegacyGateway) ? "#ff9900" :
                            isActive ? "#00e5ff" : "#334155";
        ctx.strokeStyle = strokeColor;
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
        ctx.fillStyle = (nodeKey === "router" && isLegacyGateway) ? "#ffb800" : "#e2e8f0";
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

// Step throughput chart timeline at steady 2 Hz
function tickThroughputChart() {
    if (!latestState) return;
    const bData = latestState.bearers || {};
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
}

// Update UI Components with Live Telemetry State
function renderState(state) {
    latestState = state;

    // 0. Update Modernization Lifecycle Stepper
    if (state.modernization) {
        updateModernizationUI(state.modernization);
    }

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
        if (lossEl) {
            if (b.packet_loss_pct >= 90) {
                lossEl.innerHTML = `<span style="color: #ff3344; font-weight: bold;">${b.packet_loss_pct.toFixed(1)}% SEVERED</span>`;
            } else if (b.packet_loss_pct > 10) {
                lossEl.innerHTML = `<span style="color: #ffb800; font-weight: bold;">${b.packet_loss_pct.toFixed(1)}%</span>`;
            } else {
                lossEl.innerHTML = `${b.packet_loss_pct.toFixed(1)} <span class="unit">%</span>`;
            }
        }

        const scoreEl = document.getElementById(`${key}-score`);
        if (scoreEl) scoreEl.innerText = b.score.toFixed(1);

        const tpEl = document.getElementById(`${key}-throughput`);
        if (tpEl) {
            if (b.packet_loss_pct >= 90 && b.raw_throughput_kbps > 10) {
                tpEl.innerHTML = `<span style="color: #ff3344; font-weight: bold;">0.0 <span class="unit">Kbps</span></span> <span style="font-size: 8px; color: #ff3344;">[100% DROP]</span>`;
            } else {
                tpEl.innerHTML = `${b.throughput_kbps.toFixed(1)} <span class="unit">Kbps</span>`;
            }
        }

        const dropEl = document.getElementById(`${key}-drops`);
        if (dropEl) {
            if (b.packet_loss_pct >= 90) {
                dropEl.innerHTML = `<span style="color: #ff3344; font-weight: bold;">DROPPING (100%)</span>`;
            } else {
                dropEl.innerText = b.total_dropped;
            }
        }

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

    // 5. Seed initial chart points if first load
    if (chartHistory.timestamps.length === 0) {
        const pKbps = bData.pleops ? bData.pleops.throughput_kbps : 0;
        const mKbps = bData.milsat ? bData.milsat.throughput_kbps : 0;
        const lKbps = bData.losrf ? bData.losrf.throughput_kbps : 0;
        for (let i = 0; i < 5; i++) {
            chartHistory.timestamps.push(new Date().toLocaleTimeString());
            chartHistory.pleops.push(pKbps);
            chartHistory.milsat.push(mKbps);
            chartHistory.losrf.push(lKbps);
        }
        drawThroughputChart();
    }

    // 6. Update Chaos Active Card Status in Drawer
    if (state.chaos_state) {
        updateChaosStatusCard(state.chaos_state);
    }

    // 7. Update Event Log & Fire Real-Time HUD Toasts
    if (state.recent_events && state.recent_events.length > 0) {
        const terminal = document.getElementById("events-terminal");
        const countBadge = document.getElementById("event-count");
        if (countBadge) countBadge.innerText = `${state.recent_events.length} EVENTS`;

        // Check for new high-priority events to show as HUD Toasts
        if (!isInitialStateLoad) {
            state.recent_events.forEach(evt => {
                const evtKey = `${evt.timestamp || evt.time_str}-${evt.type}-${evt.message}`;
                if (!seenEventKeys.has(evtKey)) {
                    seenEventKeys.add(evtKey);
                    if (evt.type === "CHAOS_INJECTION" || evt.type === "ROUTE_FAILOVER") {
                        showHUDToast(evt.severity, evt.type, evt.message);
                    }
                }
            });
        } else {
            state.recent_events.forEach(evt => {
                const evtKey = `${evt.timestamp || evt.time_str}-${evt.type}-${evt.message}`;
                seenEventKeys.add(evtKey);
            });
            isInitialStateLoad = false;
        }

        if (terminal) {
            terminal.innerHTML = "";
            state.recent_events.forEach((evt, idx) => {
                const entry = document.createElement("div");
                const sevClass = evt.severity === "DANGER" ? "event-danger" :
                                 evt.severity === "WARNING" ? "event-warning" :
                                 evt.severity === "SUCCESS" ? "event-success" : "event-info";
                const isNew = idx === 0 ? "event-new" : "";
                entry.className = `event-entry ${sevClass} ${isNew}`;
                entry.innerHTML = `
                    <span class="event-time">[${evt.time_str || ''}]</span>
                    <span class="event-tag">[${evt.type}]</span>
                    <span class="event-msg">${evt.message}</span>
                `;
                terminal.appendChild(entry);
            });
            terminal.scrollTop = 0;
        }
    }


    // 7. Update Quantitative Resilience Benchmark Cards & Table
    const bench = state.resilience_benchmark;
    if (bench) {
        const mttdEl = document.getElementById("bench-mttd");
        if (mttdEl) mttdEl.innerHTML = `${(bench.avg_detection_latency_ms || 4120).toLocaleString()} <span class="unit">ms</span>`;

        const cutoverEl = document.getElementById("bench-cutover");
        if (cutoverEl) cutoverEl.innerHTML = `${(bench.avg_cutover_latency_ms || 1140).toLocaleString()} <span class="unit">ms</span>`;

        const survivalEl = document.getElementById("bench-survival");
        if (survivalEl) survivalEl.innerHTML = `${(bench.avg_packet_survival_pct || 99.2).toFixed(1)} <span class="unit">%</span>`;

        const runBtn = document.getElementById("run-benchmark-btn");
        if (runBtn) {
            if (bench.is_running) {
                runBtn.disabled = true;
                runBtn.innerHTML = `<span class="btn-icon">⏳</span> EXECUTING BENCHMARKS...`;
                runBtn.style.opacity = "0.7";
            } else {
                runBtn.disabled = false;
                runBtn.innerHTML = `<span class="btn-icon">▶</span> RUN BENCHMARK SUITE`;
                runBtn.style.opacity = "1";
            }
        }

        if (bench.scenarios && bench.scenarios.length >= 3) {
            const s1 = bench.scenarios[0];
            const s2 = bench.scenarios[1];
            const s3 = bench.scenarios[2];

            const setEl = (id, val) => { const el = document.getElementById(id); if (el) el.innerText = val; };
            setEl("bench-s1-detect", `${s1.detection_time_ms.toFixed(0)} ms`);
            setEl("bench-s1-cutover", `${s1.cutover_time_ms.toFixed(0)} ms`);
            setEl("bench-s1-survival", `${s1.packet_survival_pct.toFixed(1)}%`);
            setEl("bench-s1-alt", (s1.promoted_route || "MILSAT").replace("eth-", "").toUpperCase());
            setEl("bench-s1-status", s1.status);

            setEl("bench-s2-detect", `${s2.detection_time_ms.toFixed(0)} ms`);
            setEl("bench-s2-cutover", `${s2.cutover_time_ms.toFixed(0)} ms`);
            setEl("bench-s2-survival", `${s2.packet_survival_pct.toFixed(1)}%`);
            setEl("bench-s2-alt", (s2.promoted_route || "MILSAT").replace("eth-", "").toUpperCase());
            setEl("bench-s2-status", s2.status);

            setEl("bench-s3-detect", `${s3.detection_time_ms.toFixed(0)} ms`);
            setEl("bench-s3-cutover", `${s3.cutover_time_ms.toFixed(0)} ms`);
            setEl("bench-s3-survival", `${s3.packet_survival_pct.toFixed(1)}%`);
            setEl("bench-s3-alt", `${(s3.promoted_route || "PLEOPS").replace("eth-", "").toUpperCase()} (DAMPED)`);
            setEl("bench-s3-status", s3.status);
        }
    }
}

// Interactive Benchmark Trigger
async function triggerBenchmark() {
    console.log("Triggering Resiliency Benchmark Suite...");
    const runBtn = document.getElementById("run-benchmark-btn");
    if (runBtn) {
        runBtn.disabled = true;
        runBtn.innerHTML = `<span class="btn-icon">⏳</span> EXECUTING BENCHMARKS...`;
    }
    try {
        const resp = await fetch("/api/benchmark", {
            method: "POST",
            headers: { "Content-Type": "application/json" }
        });
        const result = await resp.json();
        console.log("Benchmark Trigger Result:", result);
        pollStatus();
    } catch (err) {
        console.error("Failed to run benchmark:", err);
        if (runBtn) {
            runBtn.disabled = false;
            runBtn.innerHTML = `<span class="btn-icon">▶</span> RUN BENCHMARK SUITE`;
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
async function triggerChaos(action, target = "", btnEl = null) {
    console.log(`Triggering Chaos Action: ${action}`);

    // If btnEl not explicitly passed, try to look up by ID
    if (!btnEl) {
        if (action === "jam_pleops") btnEl = document.getElementById("btn-chaos-jam");
        else if (action === "rain_fade_milsat") btnEl = document.getElementById("btn-chaos-rain");
        else if (action === "degrade_losrf") btnEl = document.getElementById("btn-chaos-rf");
        else if (action === "flap_link") btnEl = document.getElementById("btn-chaos-flap");
        else if (action === "clean_slate") btnEl = document.getElementById("btn-chaos-clean");
        else if (action === "apply_profiles") btnEl = document.getElementById("btn-chaos-profiles");
    }

    // Instant optimistic visual feedback on the button
    let origHtml = "";
    if (btnEl) {
        origHtml = btnEl.innerHTML;
        btnEl.classList.add("btn-loading");
        btnEl.disabled = true;
        const titleEl = btnEl.querySelector(".btn-title");
        if (titleEl) titleEl.innerText = "INJECTING...";
    }

    // Immediate optimistic update of Chaos Status Card
    const card = document.getElementById("chaos-active-card");
    const title = document.getElementById("chaos-status-title");
    const desc = document.getElementById("chaos-status-desc");
    if (card && title && desc) {
        if (action === "jam_pleops") {
            card.className = "chaos-active-card status-jammed";
            title.innerText = "🚨 INJECTING: EW RF JAMMING...";
            desc.innerText = "Severing P-LEO link (100% loss). Triggering SLA route mutation...";
        } else if (action === "clean_slate") {
            card.className = "chaos-active-card";
            title.innerText = "🛡️ RESTORING: CLEAN SLATE...";
            desc.innerText = "Clearing all Netem impairments across all tactical bearers...";
        } else if (action === "rain_fade_milsat") {
            card.className = "chaos-active-card status-degraded";
            title.innerText = "🌧️ INJECTING: SATELLITE RAIN FADE...";
            desc.innerText = "Injecting 350ms delay + 15% loss on MILSAT link...";
        } else if (action === "degrade_losrf") {
            card.className = "chaos-active-card status-degraded";
            title.innerText = "📡 INJECTING: RF MULTIPATH JAM...";
            desc.innerText = "Injecting 150ms delay + 20% loss on LOS-RF link...";
        }
    }

    try {
        const resp = await fetch("/api/chaos", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ action: action, target: target })
        });
        const result = await resp.json();
        console.log("Chaos Action Result:", result);
        if (result.chaos_state) {
            updateChaosStatusCard(result.chaos_state);
        }
        // Force immediate refresh
        pollStatus();
    } catch (err) {
        console.error("Failed to inject chaos:", err);
    } finally {
        if (btnEl) {
            setTimeout(() => {
                btnEl.classList.remove("btn-loading");
                btnEl.disabled = false;
                btnEl.innerHTML = origHtml;
            }, 500);
        }
    }
}


// Interactive Modernization Lifecycle Trigger
let transitionPollTimer = null;
let lastKnownCompletedStage = null;

async function pollModernization() {
    try {
        const resp = await fetch("/api/modernization?t=" + Date.now());
        if (resp.ok) {
            const data = await resp.json();
            updateModernizationUI(data);
            if (!data.is_in_transition && transitionPollTimer) {
                clearInterval(transitionPollTimer);
                transitionPollTimer = null;
            }
        }
    } catch (e) {
        console.debug("Modernization poll error:", e);
    }
}

async function triggerModernization(action) {
    console.log(`Triggering Modernization Action: ${action}`);
    const transMsg = document.getElementById("modern-transition-msg");
    const completedMsg = document.getElementById("modern-completed-msg");
    const banner = document.getElementById("modern-alert-banner");
    const bannerText = document.getElementById("modern-alert-text");
    const bannerProg = document.getElementById("modern-alert-progress");

    // Map action to target stage
    let targetStage = 1;
    let actionLabel = "Action";
    if (action === "reset_day0") { targetStage = 1; actionLabel = "Resetting Day 0 Legacy Router"; }
    else if (action === "bootstrap_k3s") { targetStage = 2; actionLabel = "Bootstrapping K3s Node"; }
    else if (action === "init_zarf") { targetStage = 3; actionLabel = "Staging Zarf Registry"; }
    else if (action === "cutover_cnf" || action === "deploy_cnf") { targetStage = 4; actionLabel = "Atomic Hot Cutover"; }
    else if (action === "full_upgrade") { targetStage = 4; actionLabel = "Full Modernization Pipeline"; }

    // Instant optimistic UI feedback
    if (transMsg) transMsg.innerText = `[IN PROGRESS] Initiating ${actionLabel}...`;
    if (completedMsg) completedMsg.innerText = "";
    if (banner) {
        banner.className = "modern-alert-banner in-progress";
        if (bannerText) bannerText.innerText = `[SETTING UP] ${actionLabel} in progress...`;
        if (bannerProg) bannerProg.innerText = "[20%]";
    }

    // Put target card into optimistic in-progress state
    const targetCard = document.getElementById(`step-card-${targetStage}`);
    const targetStatus = document.getElementById(`step-${targetStage}-status`);
    const targetProg = document.getElementById(`step-${targetStage}-progress`);
    const targetProgFill = document.getElementById(`step-${targetStage}-progress-fill`);
    const targetBadge = document.getElementById(`step-${targetStage}-badge`);

    if (targetCard) {
        targetCard.classList.remove("current", "completed", "setup-completed", "ready-next");
        targetCard.classList.add("in-progress");
    }
    if (targetStatus) targetStatus.innerHTML = `<span class="step-spinner">⚙</span> SETTING UP (20%)...`;
    if (targetProg) targetProg.style.display = "block";
    if (targetProgFill) targetProgFill.style.width = "20%";
    if (targetBadge) targetBadge.style.display = "none";

    // Disable modern action buttons during transition
    const buttons = document.querySelectorAll(".modern-btn");
    buttons.forEach(b => b.disabled = true);

    try {
        const resp = await fetch("/api/modernization", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ action: action })
        });
        const result = await resp.json();
        console.log("Modernization Action Result:", result);
    } catch (err) {
        console.error("Failed to trigger modernization action:", err);
        if (transMsg) transMsg.innerText = "Error triggering action.";
    }

    // Start high-frequency polling while in transition
    if (transitionPollTimer) clearInterval(transitionPollTimer);
    transitionPollTimer = setInterval(pollModernization, 400);
}

// Update Modernization Stepper UI
function updateModernizationUI(modern) {
    if (!modern) return;

    const stageBadge = document.getElementById("hud-modern-stage-badge");
    const headerPostureBadge = document.getElementById("hud-header-posture-badge");
    const gatewayTag = document.getElementById("topo-gateway-tag");
    const transMsg = document.getElementById("modern-transition-msg");
    const completedMsg = document.getElementById("modern-completed-msg");
    const banner = document.getElementById("modern-alert-banner");
    const bannerIcon = document.getElementById("modern-alert-icon");
    const bannerText = document.getElementById("modern-alert-text");
    const bannerProg = document.getElementById("modern-alert-progress");

    // Update Header Posture Badge
    if (headerPostureBadge) {
        if (modern.is_in_transition) {
            headerPostureBadge.innerText = `UPGRADING: STAGE ${modern.target_stage_number || modern.stage_number}/4`;
            headerPostureBadge.className = "header-posture-badge posture-transition";
        } else if (modern.stage_number === 4) {
            headerPostureBadge.innerText = "DAY 2: CLOUD-NATIVE CNF";
            headerPostureBadge.className = "header-posture-badge posture-cnf";
        } else if (modern.stage_number === 1) {
            headerPostureBadge.innerText = "DAY 0: LEGACY VNF";
            headerPostureBadge.className = "header-posture-badge posture-legacy";
        } else {
            headerPostureBadge.innerText = `STAGE ${modern.stage_number}: ${modern.stage_name.toUpperCase()}`;
            headerPostureBadge.className = "header-posture-badge posture-transition";
        }
    }

    // Update Sidebar Panel Stage Tag
    if (stageBadge) {
        stageBadge.innerText = `STAGE ${modern.stage_number}: ${modern.stage_name.toUpperCase()}`;
        if (modern.stage_number === 1) {
            stageBadge.style.color = "#ffb800";
            stageBadge.style.borderColor = "#ffb800";
            stageBadge.style.background = "rgba(255, 184, 0, 0.15)";
        } else if (modern.stage_number === 4) {
            stageBadge.style.color = "#00ff66";
            stageBadge.style.borderColor = "#00ff66";
            stageBadge.style.background = "rgba(0, 255, 102, 0.15)";
        } else {
            stageBadge.style.color = "#00e5ff";
            stageBadge.style.borderColor = "#00e5ff";
            stageBadge.style.background = "rgba(0, 229, 255, 0.15)";
        }
    }

    // Update Topology Tag
    if (gatewayTag) {
        if (modern.gateway_type === "LEGACY_VNF") {
            gatewayTag.innerText = "GATEWAY: LEGACY VNF (STATIC METRICS) [DAY 0]";
            gatewayTag.style.color = "#ffb800";
            gatewayTag.style.borderColor = "#ffb800";
            gatewayTag.style.background = "rgba(255, 184, 0, 0.15)";
        } else {
            gatewayTag.innerText = "GATEWAY: CLOUD-NATIVE CNF (K3s DYNAMIC SDN) [DAY 2]";
            gatewayTag.style.color = "#00e5ff";
            gatewayTag.style.borderColor = "#00e5ff";
            gatewayTag.style.background = "rgba(0, 229, 255, 0.15)";
        }
    }

    // Update Sidebar Posture Status Card
    const sideMode = document.getElementById("sidebar-mode-val");
    const sideData = document.getElementById("sidebar-dataplane-val");
    if (sideMode) {
        if (modern.stage_number === 4) {
            sideMode.innerText = "DYNAMIC SLA STEERING";
            sideMode.className = "status-val highlight-cyan";
        } else if (modern.stage_number === 1) {
            sideMode.innerText = "STATIC WEIGHTED METRICS (DAY 0)";
            sideMode.className = "status-val highlight-amber";
        } else {
            sideMode.innerText = "STAGING / MIGRATION ACTIVE";
            sideMode.className = "status-val highlight-cyan";
        }
    }
    if (sideData) {
        if (modern.gateway_type === "LEGACY_VNF") {
            sideData.innerText = "LEGACY LINUX VNF (HOST)";
            sideData.className = "status-val highlight-amber";
        } else {
            sideData.innerText = "CLOUD-NATIVE CNF (K3s POD)";
            sideData.className = "status-val highlight-green";
        }
    }

    // Update Alert Banner & Transition Message
    if (modern.is_in_transition) {
        if (banner) banner.className = "modern-alert-banner in-progress";
        if (bannerIcon) bannerIcon.innerHTML = `<span class="step-spinner">⚙</span>`;
        if (bannerText) bannerText.innerText = modern.transition_message || "Modernization transition in progress...";
        if (bannerProg) bannerProg.innerText = `[${modern.progress_pct || 50}%]`;
        if (transMsg) transMsg.innerText = modern.transition_message || "Processing...";
        if (completedMsg) completedMsg.innerText = "";
    } else {
        if (banner) banner.className = "modern-alert-banner completed";
        if (bannerIcon) bannerIcon.innerHTML = `✓`;
        if (bannerText) bannerText.innerText = modern.completion_message || "Stage Operational.";
        if (bannerProg) bannerProg.innerText = modern.last_completed_at ? `[${modern.last_completed_at}]` : "[ONLINE]";
        if (transMsg) transMsg.innerText = "";
        if (completedMsg) completedMsg.innerText = modern.completion_message ? `✓ ${modern.completion_message}` : "";
    }

    // Trigger flash animation if new stage just completed
    const justCompleted = (modern.completed_stage && modern.completed_stage !== lastKnownCompletedStage && !modern.is_in_transition);
    if (justCompleted) {
        lastKnownCompletedStage = modern.completed_stage;
    }

    // Update 4 Stage Cards based on backend stage_statuses or stage_number
    const statuses = modern.stage_statuses || {};
    const curStage = modern.stage_number || 1;
    const targetStage = modern.target_stage_number || curStage;

    for (let i = 1; i <= 4; i++) {
        const card = document.getElementById(`step-card-${i}`);
        const statusEl = document.getElementById(`step-${i}-status`);
        const badgeEl = document.getElementById(`step-${i}-badge`);
        const progEl = document.getElementById(`step-${i}-progress`);
        const progFill = document.getElementById(`step-${i}-progress-fill`);
        const detailEl = document.getElementById(`step-${i}-detail`);
        const conn = document.getElementById(`step-conn-${i}`);

        if (!card) continue;

        const st = statuses[String(i)] || (i < curStage ? "SETUP_COMPLETED" : (i === curStage ? "ACTIVE" : "PENDING"));

        card.className = "sidebar-stage-card";

        if (modern.is_in_transition && i === targetStage) {
            // Actively setting up stage
            card.classList.add("in-progress");
            if (statusEl) {
                const actionVerb = (i === 4) ? "CUTTING OVER" : (i === 2 ? "BOOTSTRAPPING" : (i === 3 ? "STAGING" : "RESETTING"));
                statusEl.innerHTML = `<span class="step-spinner">⚙</span> ${actionVerb} (${modern.progress_pct || 40}%)...`;
            }
            if (badgeEl) badgeEl.style.display = "none";
            if (progEl) progEl.style.display = "block";
            if (progFill) progFill.style.width = `${modern.progress_pct || 40}%`;
            if (detailEl) detailEl.innerText = modern.transition_message || "Executing setup...";
        } else if (st === "SETUP_COMPLETED") {
            // Stage completed setup
            card.classList.add("setup-completed");
            if (justCompleted && i === modern.completed_stage) {
                card.classList.add("completed-flash");
            }
            if (statusEl) {
                if (i === 1) statusEl.innerText = "ACTIVE (DAY 0)";
                else if (i === 2) statusEl.innerText = "✓ NODE READY";
                else if (i === 3) statusEl.innerText = "✓ REGISTRY READY";
                else if (i === 4) statusEl.innerText = "✓ CNF OPERATIONAL";
                else statusEl.innerText = "✓ SETUP COMPLETED";
            }
            if (badgeEl) {
                badgeEl.style.display = "inline-flex";
                badgeEl.innerText = (i === 4) ? "✓ ACTIVE CNF" : (i === 3 ? "✓ STAGED" : (i === 2 ? "✓ READY" : "✓ COMPLETED"));
            }
            if (progEl) progEl.style.display = "none";
            if (detailEl) {
                if (i === 2) detailEl.innerText = "K3s Node Ready • Dataplane Intact";
                else if (i === 3) detailEl.innerText = "Seed Registry Online • Staged";
                else if (i === 4) detailEl.innerText = "Dynamic SLA Steering Active (0ms Loss)";
            }
        } else if (st === "ACTIVE") {
            // Active Day 0 legacy baseline
            card.classList.add("current");
            if (statusEl) statusEl.innerText = (i === 1) ? "ACTIVE (DAY 0)" : "OPERATIONAL";
            if (badgeEl) {
                badgeEl.style.display = "inline-flex";
                badgeEl.innerText = (i === 1) ? "✓ DAY 0 ACTIVE" : "✓ ACTIVE";
            }
            if (progEl) progEl.style.display = "none";
            if (detailEl && i === 1) detailEl.innerText = "Static Metric Dataplane";
        } else if (st === "RETIRED") {
            // Retired legacy stage
            card.classList.add("retired");
            if (statusEl) statusEl.innerText = "RETIRED";
            if (badgeEl) badgeEl.style.display = "none";
            if (progEl) progEl.style.display = "none";
            if (detailEl && i === 1) detailEl.innerText = "Decommissioned Legacy VNF";
        } else if (st === "READY") {
            // Ready for next action
            card.classList.add("ready-next");
            if (statusEl) statusEl.innerText = (i === 3) ? "READY TO STAGE" : "READY FOR CUTOVER";
            if (badgeEl) badgeEl.style.display = "none";
            if (progEl) progEl.style.display = "none";
            if (detailEl) detailEl.innerText = "Awaiting operator trigger";
        } else {
            // Pending future stage
            if (statusEl) statusEl.innerText = "PENDING";
            if (badgeEl) badgeEl.style.display = "none";
            if (progEl) progEl.style.display = "none";
            if (detailEl) detailEl.innerText = "Awaiting prior stages";
        }

        // Connector lines
        if (conn) {
            if (i < curStage || (statuses[String(i)] === "SETUP_COMPLETED" && statuses[String(i + 1)] !== "PENDING")) {
                conn.classList.add("active");
            } else {
                conn.classList.remove("active");
            }
        }
    }

    // Toggle button disabled state and highlight recommended next action
    const buttons = document.querySelectorAll(".modern-btn");
    buttons.forEach(b => {
        b.disabled = modern.is_in_transition;
        b.classList.remove("btn-recommended");
    });

    if (!modern.is_in_transition) {
        if (curStage === 1) {
            const btn = document.getElementById("btn-step-k3s");
            if (btn) btn.classList.add("btn-recommended");
        } else if (curStage === 2) {
            const btn = document.getElementById("btn-step-zarf");
            if (btn) btn.classList.add("btn-recommended");
        } else if (curStage === 3) {
            const btn = document.getElementById("btn-step-cutover");
            if (btn) btn.classList.add("btn-recommended");
        } else if (curStage === 4) {
            const btn = document.getElementById("btn-step-reset");
            if (btn) btn.classList.add("btn-recommended");
        }
    }
}

// ============================================================================
// DOCKED MISSION CONTROL SIDEBAR CONTROLLER (UPGRADE, CHAOS, LOGS)
// ============================================================================
let sidebarOpen = false;
let currentSidebarTab = "upgrade"; // 'upgrade' | 'chaos' | 'logs'
let logPollTimer = null;
let currentSourceFilter = "ALL";
let currentSearchQuery = "";
let autoScrollEnabled = true;
let cachedLogs = [];
let latestLogId = 0;

function toggleSidebar(tab) {
    if (sidebarOpen && (!tab || tab === currentSidebarTab)) {
        closeSidebar();
    } else {
        openSidebar(tab || currentSidebarTab);
    }
}

function openSidebar(tab) {
    sidebarOpen = true;
    document.body.classList.add("sidebar-open");
    const sidebar = document.getElementById("hud-sidebar");
    if (sidebar) sidebar.classList.add("open");

    if (tab) {
        switchSidebarTab(tab);
    }

    triggerLayoutResize();

    // If active tab is logs, poll at 1s interval
    if (currentSidebarTab === "logs") {
        fetchBackendLogs();
        if (logPollTimer) clearInterval(logPollTimer);
        logPollTimer = setInterval(fetchBackendLogs, 1000);
    }
}

function closeSidebar() {
    sidebarOpen = false;
    document.body.classList.remove("sidebar-open");
    const sidebar = document.getElementById("hud-sidebar");
    if (sidebar) sidebar.classList.remove("open");

    triggerLayoutResize();

    // Slower 5-second polling when collapsed
    if (logPollTimer) clearInterval(logPollTimer);
    logPollTimer = setInterval(fetchBackendLogs, 5000);
}

function switchSidebarTab(tab) {
    currentSidebarTab = tab || "upgrade";

    if (!sidebarOpen) {
        sidebarOpen = true;
        document.body.classList.add("sidebar-open");
        const sidebar = document.getElementById("hud-sidebar");
        if (sidebar) sidebar.classList.add("open");
        triggerLayoutResize();
    }

    // Toggle tab navigation buttons and body panels
    const tabs = ["upgrade", "chaos", "logs"];
    tabs.forEach(t => {
        const btn = document.getElementById(`tab-btn-${t}`);
        const panel = document.getElementById(`panel-${t}`);
        if (btn) {
            if (t === currentSidebarTab) btn.classList.add("active");
            else btn.classList.remove("active");
        }
        if (panel) {
            if (t === currentSidebarTab) panel.classList.add("active");
            else panel.classList.remove("active");
        }
    });

    if (currentSidebarTab === "logs") {
        fetchBackendLogs();
        if (logPollTimer) clearInterval(logPollTimer);
        logPollTimer = setInterval(fetchBackendLogs, 1000);
    } else {
        if (logPollTimer) clearInterval(logPollTimer);
        logPollTimer = setInterval(fetchBackendLogs, 5000);
    }
}

function triggerLayoutResize() {
    window.dispatchEvent(new Event("resize"));
    setTimeout(() => {
        drawTopology();
        drawThroughputChart();
    }, 50);
    setTimeout(() => {
        drawTopology();
        drawThroughputChart();
    }, 360);
}

// Global hotkeys:
// 'U' or '1' -> Upgrade tab
// 'C' or '2' -> Chaos tab
// 'L' or '3' -> Logs tab
// 'Escape' -> Close sidebar
window.addEventListener("keydown", (e) => {
    if (["INPUT", "TEXTAREA"].includes(document.activeElement.tagName)) return;

    if (e.key === "Escape" && sidebarOpen) {
        closeSidebar();
    } else if (e.key === "u" || e.key === "U" || e.key === "1") {
        toggleSidebar("upgrade");
    } else if (e.key === "c" || e.key === "C" || e.key === "2") {
        toggleSidebar("chaos");
    } else if (e.key === "l" || e.key === "L" || e.key === "3") {
        toggleSidebar("logs");
    }
});

async function fetchBackendLogs() {
    try {
        const resp = await fetch("/api/logs?tail=300&t=" + Date.now());
        if (!resp.ok) return;
        const data = await resp.json();
        const logs = data.logs || [];
        cachedLogs = logs;
        latestLogId = data.latest_id || 0;

        // Update badge counts across all UI surfaces
        const headerBadge = document.getElementById("header-log-badge");
        const floatingBadge = document.getElementById("floating-log-badge");
        const sidebarTabBadge = document.getElementById("sidebar-tab-log-badge");
        const countTotal = document.getElementById("log-count-total");
        const totalCount = data.total_count || logs.length;

        if (headerBadge) headerBadge.innerText = totalCount;
        if (floatingBadge) floatingBadge.innerText = totalCount;
        if (sidebarTabBadge) sidebarTabBadge.innerText = totalCount;
        if (countTotal) countTotal.innerText = totalCount;

        if (sidebarOpen && currentSidebarTab === "logs") {
            renderLogTerminal();
        }
    } catch (err) {
        console.debug("Log fetch error:", err);
    }
}

function renderLogTerminal() {
    const terminalContent = document.getElementById("drawer-terminal-content");
    const filteredCountEl = document.getElementById("log-count-filtered");
    const terminal = document.getElementById("log-drawer-terminal");
    if (!terminalContent) return;

    let filtered = cachedLogs;

    // Filter by source
    if (currentSourceFilter && currentSourceFilter !== "ALL") {
        filtered = filtered.filter(item => (item.source || "").toUpperCase() === currentSourceFilter);
    }

    // Filter by search query
    if (currentSearchQuery) {
        const q = currentSearchQuery.toLowerCase();
        filtered = filtered.filter(item => 
            (item.message || "").toLowerCase().includes(q) ||
            (item.source || "").toLowerCase().includes(q) ||
            (item.level || "").toLowerCase().includes(q)
        );
    }

    if (filteredCountEl) filteredCountEl.innerText = filtered.length;

    if (filtered.length === 0) {
        terminalContent.innerHTML = `
            <div class="log-entry log-info" style="opacity: 0.6; padding: 12px 0;">
                <span class="log-msg">No log entries matching filter (${currentSourceFilter})</span>
            </div>
        `;
        return;
    }

    const html = filtered.map(item => {
        const lvl = (item.level || "INFO").toLowerCase();
        const timeStr = item.time_str || "--:--:--Z";
        const src = item.source || "SYS";
        const msg = escapeHtml(item.message || "");
        return `
            <div class="log-entry log-${lvl}">
                <span class="log-time">[${timeStr}]</span>
                <span class="log-source">[${src}]</span>
                <span class="log-level">[${item.level || 'INFO'}]</span>
                <span class="log-msg">${msg}</span>
            </div>
        `;
    }).join("");

    terminalContent.innerHTML = html;

    if (autoScrollEnabled && terminal) {
        terminal.scrollTop = terminal.scrollHeight;
    }
}

function setLogSourceFilter(filter) {
    currentSourceFilter = filter.toUpperCase();
    const pills = document.querySelectorAll("#log-filter-pills .pill");
    pills.forEach(p => {
        if (p.getAttribute("data-filter") === currentSourceFilter) {
            p.classList.add("active");
        } else {
            p.classList.remove("active");
        }
    });
    renderLogTerminal();
}

function onLogSearchInput() {
    const input = document.getElementById("log-search-input");
    currentSearchQuery = (input ? input.value : "").trim();
    renderLogTerminal();
}

function toggleAutoScroll(enabled) {
    autoScrollEnabled = Boolean(enabled);
}

async function clearLogsOnServer() {
    try {
        await fetch("/api/logs/clear", { method: "POST" });
        cachedLogs = [];
        renderLogTerminal();
        fetchBackendLogs();
    } catch (err) {
        console.error("Failed to clear logs:", err);
    }
}

function copyLogsToClipboard() {
    if (!cachedLogs || cachedLogs.length === 0) return;
    const text = cachedLogs.map(item => `[${item.time_str || ''}] [${item.source || ''}] [${item.level || ''}] ${item.message || ''}`).join("\n");
    navigator.clipboard.writeText(text).then(() => {
        const copyBtn = document.getElementById("btn-copy-logs");
        if (copyBtn) {
            const orig = copyBtn.innerText;
            copyBtn.innerText = "✓ COPIED!";
            setTimeout(() => { copyBtn.innerText = orig; }, 1500);
        }
    }).catch(err => {
        console.error("Clipboard copy failed:", err);
    });
}

function escapeHtml(str) {
    return str
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
        .replace(/'/g, "&#039;");
}

// Initialization on Page Load
window.addEventListener("DOMContentLoaded", () => {
    // Initial draw
    requestAnimationFrame(drawTopology);
    drawThroughputChart();

    // Start strict 2 Hz throughput chart ticker
    setInterval(tickThroughputChart, 500);

    // Initial Modernization Status Fetch
    pollModernization();

    // Start SSE Telemetry
    startSSE();

    // Initial backend log fetch & background badge polling (5s)
    fetchBackendLogs();
    if (logPollTimer) clearInterval(logPollTimer);
    logPollTimer = setInterval(fetchBackendLogs, 5000);
});
