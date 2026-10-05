#!/usr/bin/env bash
# ==============================================================================
# OpenTofu Sandbox Runner Wrapper
# Automatically ensures tunnel is active and executes tofu commands
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TOFU_DIR="$PROJECT_ROOT/infra/tofu"

# Ensure tunnel is active
"$SCRIPT_DIR/sandbox-tunnel.sh" start

# Run tofu in infra/tofu directory with all passed arguments
cd "$TOFU_DIR"
tofu "$@"
