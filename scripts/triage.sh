#!/bin/bash
# Turbo-Heartbeat: Main Triage Script
# Collects signals, sends to triage model, acts on decision
#
# Universal OpenAI-compatible /v1/chat/completions API — works with:
# Ollama, LM Studio, llama.cpp, vLLM, LocalAI, Jan, Groq, Mistral,
# OpenRouter, OpenAI, and any other OpenAI-compatible endpoint.
#
# Single code path for the API call. Only variables: api_base, api_key, model.
# Thinking models (GLM, DeepSeek-R1, QwQ) need disable_thinking: true in config
# which adds a native Ollama pre-call to suppress reasoning tokens.
#
# Usage: triage.sh [config.yaml]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG="${1:-$SKILL_DIR/config.yaml}"
LOG_FILE="$SKILL_DIR/stats/triage.log"
PROMPT_FILE="$SKILL_DIR/templates/triage-prompt.md"

mkdir -p "$(dirname "$LOG_FILE")"

# --- Config ---
read_config() {
    local key="$1" default="$2"
    grep -oP "^\s*${key}:\s*\K.*" "$CONFIG" 2>/dev/null | tr -d '"' || echo "$default"
}

MODEL=$(read_config "model" "gemma3:4b")
API_BASE=$(read_config "api_base" "http://localhost:11434/v1")
API_KEY=$(read_config "api_key" "no-key")
COOLDOWN=$(read_config "cooldown_seconds" "300")
QUIET_START=$(read_config "quiet_start" "23:00")
QUIET_END=$(read_config "quiet_end" "08:00")
DISABLE_THINKING=$(read_config "disable_thinking" "false")
INTERVAL=$(read_config "interval_seconds" "30")
KEEP_ALIVE_CFG=$(read_config "keep_alive" "auto")

# Calculate Ollama keep_alive (seconds)
# Auto: interval + 120s buffer (minimum 300s = Ollama default)
if [ "$KEEP_ALIVE_CFG" = "auto" ]; then
    KEEP_ALIVE=$(( INTERVAL + 120 ))
    [ "$KEEP_ALIVE" -lt 300 ] && KEEP_ALIVE=300
else
    KEEP_ALIVE="$KEEP_ALIVE_CFG"
fi

# --- Quiet hours ---
CURRENT_HOUR=$(date +%H)
QUIET_START_H=${QUIET_START%%:*}
QUIET_END_H=${QUIET_END%%:*}
IN_QUIET_HOURS=false
if [ "$CURRENT_HOUR" -ge "$QUIET_START_H" ] || [ "$CURRENT_HOUR" -lt "$QUIET_END_H" ]; then
    IN_QUIET_HOURS=true
fi

# --- Cooldown ---
LAST_ESCALATION_FILE="$SKILL_DIR/stats/.last_escalation"
if [ -f "$LAST_ESCALATION_FILE" ]; then
    LAST_TS=$(cat "$LAST_ESCALATION_FILE")
    NOW_TS=$(date +%s)
    DIFF=$((NOW_TS - LAST_TS))
    if [ "$DIFF" -lt "$COOLDOWN" ]; then
        echo "$(date -Is) OK cooldown=${DIFF}s/${COOLDOWN}s" >> "$LOG_FILE"
        exit 0
    fi
fi

# --- Collect signals ---
SIGNALS=""
for collector in "$SCRIPT_DIR/signals/"*.sh; do
    [ -x "$collector" ] || continue
    COLLECTOR_NAME=$(basename "$collector" .sh)
    
    # Quiet hours: only system-critical collectors
    if [ "$IN_QUIET_HOURS" = true ] && [ "$COLLECTOR_NAME" != "system" ]; then
        continue
    fi
    
    SIGNAL_OUTPUT=$(bash "$collector" 2>/dev/null || echo "${COLLECTOR_NAME}: ERROR")
    SIGNALS="${SIGNALS}${SIGNAL_OUTPUT}\n"
done

if [ -z "$SIGNALS" ]; then
    echo "$(date -Is) OK no_signals quiet=$IN_QUIET_HOURS" >> "$LOG_FILE"
    exit 0
fi

# --- Build JSON payload ---
PROMPT=$(cat "$PROMPT_FILE")
SYSTEM_JSON=$(echo "$PROMPT" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))')
USER_JSON=$(echo -e "$SIGNALS" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))')

# --- Call triage model ---
# For thinking models on Ollama: use native /api/chat with think:false
# This is the ONLY provider-specific path — needed because Ollama's OpenAI-compat
# endpoint ignores think:false and wastes tokens on reasoning.
# For everything else: standard /v1/chat/completions
START_MS=$(date +%s%N)

if [ "$DISABLE_THINKING" = "true" ]; then
    # Detect if target is actually Ollama (has /api/tags)
    OLLAMA_BASE="${API_BASE%/v1}"
    OLLAMA_BASE="${OLLAMA_BASE%/}"
    IS_OLLAMA=false
    curl -s --max-time 2 "${OLLAMA_BASE}/api/tags" &>/dev/null && IS_OLLAMA=true
    
    if [ "$IS_OLLAMA" = true ]; then
        # Ollama native API with think:false — saves ~150 tokens per call
        RESPONSE=$(curl -s --max-time 60 -X POST "${OLLAMA_BASE}/api/chat" \
            -H "Content-Type: application/json" \
            -d "{
                \"model\": \"${MODEL}\",
                \"messages\": [
                    {\"role\": \"system\", \"content\": ${SYSTEM_JSON}},
                    {\"role\": \"user\", \"content\": ${USER_JSON}}
                ],
                \"stream\": false,
                \"think\": false,
                \"keep_alive\": \"${KEEP_ALIVE}s\",
                \"options\": {\"temperature\": 0.1, \"num_predict\": 100}
            }" 2>/dev/null) || {
            echo "$(date -Is) ERROR api_unreachable url=${OLLAMA_BASE}/api/chat" >> "$LOG_FILE"
            exit 1
        }
        
        DECISION=$(echo "$RESPONSE" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    c = d.get('message', {}).get('content', '').strip()
    print(c.split('\n')[0] if c else 'ERROR: empty_content')
except Exception as e:
    print(f'ERROR: {e}')
" 2>/dev/null)
    else
        # Not actually Ollama — fall through to standard path with extra tokens
        DISABLE_THINKING="false"
    fi
fi

if [ "$DISABLE_THINKING" != "true" ]; then
    # Standard OpenAI-compatible API — universal path
    API_URL="${API_BASE%/}/chat/completions"
    
    PAYLOAD=$(cat <<EOF
{
    "model": "${MODEL}",
    "messages": [
        {"role": "system", "content": ${SYSTEM_JSON}},
        {"role": "user", "content": ${USER_JSON}}
    ],
    "max_tokens": 100,
    "temperature": 0.1,
    "stream": false,
    "keep_alive": "${KEEP_ALIVE}s"
}
EOF
)
    
    RESPONSE=$(curl -s --max-time 60 -X POST "$API_URL" \
        -H "Authorization: Bearer ${API_KEY}" \
        -H "Content-Type: application/json" \
        -d "$PAYLOAD" 2>/dev/null) || {
        echo "$(date -Is) ERROR api_unreachable url=$API_URL" >> "$LOG_FILE"
        exit 1
    }
    
    DECISION=$(echo "$RESPONSE" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    choices = d.get('choices', [])
    if choices:
        msg = choices[0].get('message', {}).get('content', '')
        if msg:
            print(msg.strip().split('\n')[0])
        else:
            print('ERROR: empty_content')
    elif 'error' in d:
        print(f'ERROR: {d[\"error\"].get(\"message\", str(d[\"error\"]))}')
    else:
        print('ERROR: unexpected_response')
except Exception as e:
    print(f'ERROR: {e}')
" 2>/dev/null)
fi

END_MS=$(date +%s%N)
LATENCY_MS=$(( (END_MS - START_MS) / 1000000 ))

# --- Act on decision ---
DECISION=$(echo "$DECISION" | tr -d '\r' | head -1)

case "$DECISION" in
    ESCALATE:*)
        REASON="${DECISION#ESCALATE: }"
        echo "$(date -Is) ESCALATE reason=\"$REASON\" latency_ms=$LATENCY_MS quiet=$IN_QUIET_HOURS" >> "$LOG_FILE"
        date +%s > "$LAST_ESCALATION_FILE"
        
        if [ "$IN_QUIET_HOURS" = true ]; then
            # Generate remediation guidance based on alert type
            GUIDANCE="Please check your system."
            case "$REASON" in
                *disk*|*Disk*|*storage*)
                    GUIDANCE="Disk usage is critical. Run 'df -h' to check. Consider removing old logs/files or expanding storage." ;;
                *memory*|*Memory*|*RAM*)
                    GUIDANCE="Memory usage is critical. Run 'free -h' and 'top' to identify the culprit." ;;
                *ollama*|*Ollama*|*inference*)
                    GUIDANCE="Local inference engine is not running. Restart it to restore triage functionality." ;;
                *gateway*|*openclaw*)
                    GUIDANCE="OpenClaw gateway appears down. Run 'openclaw gateway start'." ;;
            esac
            
            bash "$SCRIPT_DIR/notify-critical.sh" "$REASON" "$GUIDANCE"
            bash "$SCRIPT_DIR/escalate.sh" "[QUIET-HOURS CRITICAL] $REASON"
        else
            bash "$SCRIPT_DIR/escalate.sh" "$REASON"
        fi
        ;;
    DEFER:*)
        REASON="${DECISION#DEFER: }"
        echo "$(date -Is) DEFER reason=\"$REASON\" latency_ms=$LATENCY_MS quiet=$IN_QUIET_HOURS" >> "$LOG_FILE"
        ;;
    OK*)
        echo "$(date -Is) OK latency_ms=$LATENCY_MS quiet=$IN_QUIET_HOURS" >> "$LOG_FILE"
        ;;
    ERROR*)
        echo "$(date -Is) ERROR decision=\"$DECISION\" latency_ms=$LATENCY_MS quiet=$IN_QUIET_HOURS" >> "$LOG_FILE"
        ;;
    *)
        echo "$(date -Is) UNKNOWN decision=\"$DECISION\" latency_ms=$LATENCY_MS quiet=$IN_QUIET_HOURS" >> "$LOG_FILE"
        ;;
esac
