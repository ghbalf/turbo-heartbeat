#!/bin/bash
# Turbo-Heartbeat: Escalation — Send wake event to OpenClaw
# Usage: escalate.sh "<reason>"
#
# Uses `openclaw system event` CLI command for reliable escalation.
# Falls back to direct WebSocket if CLI is not available.

set -euo pipefail

REASON="${1:-Triage escalation}"
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="$SKILL_DIR/config.yaml"

# Read config helper
read_config() {
    local key="$1"
    local default="$2"
    grep -oP "^\s*${key}:\s*\K.*" "$CONFIG" 2>/dev/null | tr -d '"' || echo "$default"
}

GATEWAY_PORT=$(read_config "gateway_port" "18789")
GATEWAY_TOKEN=$(read_config "gateway_token" "")

# Try to get token from OpenClaw config if not in our config
if [ -z "$GATEWAY_TOKEN" ] && [ -f "$HOME/.openclaw/openclaw.json" ]; then
    GATEWAY_TOKEN=$(python3 -c "
import json
with open('$HOME/.openclaw/openclaw.json') as f:
    c = json.load(f)
print(c.get('gateway',{}).get('auth',{}).get('token',''))
" 2>/dev/null || echo "")
fi

EVENT_TEXT="[Turbo-HB] ${REASON}"

# Method 1: Use openclaw CLI (preferred)
if command -v openclaw &>/dev/null; then
    CMD=(openclaw system event --text "$EVENT_TEXT" --mode now --json)
    
    if [ -n "$GATEWAY_TOKEN" ]; then
        CMD+=(--token "$GATEWAY_TOKEN")
    fi
    
    RESULT=$("${CMD[@]}" 2>&1) || {
        echo "ESCALATION via CLI failed: $RESULT" >&2
        exit 1
    }
    
    echo "ESCALATED: $REASON (via openclaw CLI)"
    exit 0
fi

# Method 2: Direct WebSocket (fallback, unlikely to be needed)
echo "ESCALATION FAILED: openclaw CLI not found" >&2
echo "Install OpenClaw or ensure it's in PATH" >&2
exit 1
