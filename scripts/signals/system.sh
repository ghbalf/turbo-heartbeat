#!/bin/bash
# Signal Collector: System Health
# Checks disk usage, memory, and critical processes

set -euo pipefail

# Configurable thresholds (can be overridden via env)
DISK_THRESHOLD=${DISK_THRESHOLD:-90}
MEM_THRESHOLD=${MEM_THRESHOLD:-95}

ALERTS=""

# Check disk usage (root partition)
DISK_USAGE=$(df / | awk 'NR==2{print int($5)}')
if [ "$DISK_USAGE" -ge "$DISK_THRESHOLD" ]; then
    ALERTS="${ALERTS}disk ${DISK_USAGE}% full; "
fi

# Check memory usage
MEM_USAGE=$(free | awk '/^Mem:/{printf "%d", $3/$2 * 100}')
if [ "$MEM_USAGE" -ge "$MEM_THRESHOLD" ]; then
    ALERTS="${ALERTS}memory ${MEM_USAGE}%; "
fi

# Check if Ollama is running (if expected)
if command -v ollama &>/dev/null; then
    if ! pgrep -x "ollama" &>/dev/null; then
        ALERTS="${ALERTS}ollama not running; "
    fi
fi

# Check if OpenClaw gateway is running (systemd or process)
if ! systemctl is-active --quiet openclaw-gateway 2>/dev/null; then
    if ! pgrep -f "openclaw-gateway" &>/dev/null; then
        ALERTS="${ALERTS}openclaw-gateway down; "
    fi
fi

# Output
if [ -n "$ALERTS" ]; then
    echo "SYSTEM: ALERT — ${ALERTS%%; }"
else
    echo "SYSTEM: OK"
fi
