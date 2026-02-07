#!/bin/bash
# Turbo-Heartbeat: Environment Detection
# Outputs JSON with system capabilities for assistant-guided setup

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Detect OS and architecture
OS=$(uname -s)
ARCH=$(uname -m)
HOSTNAME=$(hostname)

# Check available RAM (in MB)
if command -v free &>/dev/null; then
    TOTAL_RAM_MB=$(free -m | awk '/^Mem:/{print $2}')
    FREE_RAM_MB=$(free -m | awk '/^Mem:/{print $7}')
else
    TOTAL_RAM_MB=0
    FREE_RAM_MB=0
fi

# Check available disk (in GB)
FREE_DISK_GB=$(df -BG / | awk 'NR==2{print int($4)}')

# Check CPU cores
CPU_CORES=$(nproc 2>/dev/null || echo 1)

# Detect if Raspberry Pi
IS_RPI=false
if [ -f /proc/device-tree/model ]; then
    MODEL=$(cat /proc/device-tree/model 2>/dev/null || echo "")
    if echo "$MODEL" | grep -qi "raspberry"; then
        IS_RPI=true
    fi
fi

# Check Ollama
OLLAMA_INSTALLED=false
OLLAMA_VERSION=""
OLLAMA_RUNNING=false
OLLAMA_MODELS="[]"

if command -v ollama &>/dev/null; then
    OLLAMA_INSTALLED=true
    OLLAMA_VERSION=$(ollama --version 2>/dev/null | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
    
    # Check if Ollama is running
    if curl -s http://localhost:11434/api/tags &>/dev/null; then
        OLLAMA_RUNNING=true
        # Get model list
        OLLAMA_MODELS=$(curl -s http://localhost:11434/api/tags 2>/dev/null | \
            python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    models = [{'name': m['name'], 'size_gb': round(m.get('size',0)/1e9, 1)} for m in data.get('models',[])]
    print(json.dumps(models))
except:
    print('[]')
" 2>/dev/null || echo "[]")
    fi
fi

# Check OpenClaw
OPENCLAW_RUNNING=false
OPENCLAW_VERSION=""
if command -v openclaw &>/dev/null; then
    OPENCLAW_VERSION=$(openclaw --version 2>/dev/null || echo "unknown")
fi
if systemctl is-active --quiet openclaw-gateway 2>/dev/null; then
    OPENCLAW_RUNNING=true
fi

# Check for common tools
HAS_CURL=$(command -v curl &>/dev/null && echo true || echo false)
HAS_JQ=$(command -v jq &>/dev/null && echo true || echo false)
HAS_PYTHON3=$(command -v python3 &>/dev/null && echo true || echo false)
HAS_GCALCLI=$(command -v gcalcli &>/dev/null && echo true || echo false)

# Determine recommended profile
RECOMMENDED_PROFILE="B"
RECOMMENDED_MODEL=""
RECOMMENDED_INTERVAL=300
PROFILE_REASON=""

if [ "$OLLAMA_INSTALLED" = true ] && [ "$OLLAMA_RUNNING" = true ]; then
    if [ "$IS_RPI" = true ] || [ "$FREE_RAM_MB" -lt 2000 ]; then
        RECOMMENDED_PROFILE="C"
        RECOMMENDED_MODEL="functiongemma"
        RECOMMENDED_INTERVAL=60
        PROFILE_REASON="Ollama available but limited RAM — FunctionGemma (270M) is ideal"
    elif [ "$FREE_RAM_MB" -ge 4000 ]; then
        RECOMMENDED_PROFILE="A"
        RECOMMENDED_MODEL="gemma3:4b"
        RECOMMENDED_INTERVAL=30
        PROFILE_REASON="Ollama available with sufficient RAM for standard local model"
    else
        RECOMMENDED_PROFILE="A"
        RECOMMENDED_MODEL="llama3.2:3b"
        RECOMMENDED_INTERVAL=30
        PROFILE_REASON="Ollama available, using smaller model for available RAM"
    fi
else
    RECOMMENDED_PROFILE="B"
    RECOMMENDED_MODEL="llama-3.3-70b (via Groq)"
    RECOMMENDED_INTERVAL=300
    PROFILE_REASON="No local Ollama — remote triage recommended"
fi

# Output JSON
cat <<EOF
{
  "system": {
    "os": "$OS",
    "arch": "$ARCH",
    "hostname": "$HOSTNAME",
    "is_rpi": $IS_RPI,
    "cpu_cores": $CPU_CORES,
    "total_ram_mb": $TOTAL_RAM_MB,
    "free_ram_mb": $FREE_RAM_MB,
    "free_disk_gb": $FREE_DISK_GB
  },
  "ollama": {
    "installed": $OLLAMA_INSTALLED,
    "version": "$OLLAMA_VERSION",
    "running": $OLLAMA_RUNNING,
    "models": $OLLAMA_MODELS
  },
  "openclaw": {
    "running": $OPENCLAW_RUNNING,
    "version": "$OPENCLAW_VERSION"
  },
  "tools": {
    "curl": $HAS_CURL,
    "jq": $HAS_JQ,
    "python3": $HAS_PYTHON3,
    "gcalcli": $HAS_GCALCLI
  },
  "recommendation": {
    "profile": "$RECOMMENDED_PROFILE",
    "model": "$RECOMMENDED_MODEL",
    "interval_seconds": $RECOMMENDED_INTERVAL,
    "reason": "$PROFILE_REASON"
  }
}
EOF
