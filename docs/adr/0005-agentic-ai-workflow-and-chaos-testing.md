# 5. Agentic AI Workflow and Chaos / DDIL Testing

Date: 2026-10-05

## Status
Accepted

## Context
Validating network resiliency for naval and tactical environments requires testing software behavior under harsh, unpredictable network conditions: sudden radio link drops, satellite rain fade, high packet jitter, and out-of-order delivery. Manually crafting exhaustive test permutations is slow and error-prone.

## Decision
1. **Agentic AI Workflow:** Utilize agentic AI tools (Claude / Cursor / Antigravity) to assist in:
   - Codebase archaeology and structural decomposition of legacy routing scripts.
   - Generating STIG remediation patches and boundary validations.
   - Scaffolding automated chaos test suites and network topology definitions.
2. **Chaos / DDIL Testing Harness:** Build a dedicated Python-based chaos engine using Linux `tc` (traffic control) and `netem` to inject synthetic impairment (latency spikes, 20-50% packet drops, link flapping) on simulated radio bridges.
3. Validate that the SD-WAN controller detects degradation within configured SLA windows and switches traffic to healthy paths without dropping application connections.

## Consequences
- **Positive:**
  - Accelerates engineering cycles and increases test coverage across edge-case failure modes.
  - Generates verifiable quantitative benchmarks (failover latency, packet loss percentage under chaos).
  - Demonstrates repeatable, automated workflows for rapid tactical edge software verification.
- **Negative:**
  - Synthetic network impairments must be carefully isolated to virtual bridge interfaces to avoid disrupting the host hypervisor's management network.
