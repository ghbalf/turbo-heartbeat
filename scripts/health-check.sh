#!/bin/bash
# Turbo-Heartbeat: Health Check
# Verifies triage model is responsive

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG="$SKILL_DIR/config.yaml"

# Read config
read_config() {
    local key="$1"
    local default="$2"
    grep -oP "^\s*${key}:\s*\K.*" "$CONFIG" 2>/dev/null | tr -d '"' || echo "$default"
}

PROVIDER=$(read_config "provider" "ollama")
MODEL=$(read_config "model" "gemma3:4b")

case "$PROVIDER" in
    ollama)
        # Check if Ollama is running
        if ! curl -s http://localhost:11434/api/tags &>/dev/null; then
            echo "HEALTH: FAIL — Ollama not responding"
            
            # Try to restart
            if command -v systemctl &>/dev/null; then
                sudo systemctl restart ollama 2>/dev/null && \
                    echo "HEALTH: Ollama restarted" || \
                    echo "HEALTH: Ollama restart failed"
            fi
            exit 1
        fi
        
        # Quick inference test
        RESPONSE=$(echo "Say OK" | timeout 15 ollama run "$MODEL" 2>/dev/null || echo "TIMEOUT")
        if [ "$RESPONSE" = "TIMEOUT" ]; then
            echo "HEALTH: FAIL — Model $MODEL timed out"
            exit 1
        fi
        
        echo "HEALTH: OK — Ollama + $MODEL responsive"
        ;;
    
    ollama-cloud|groq|mistral|openrouter|openai|gemini)
        # For remote: just check API connectivity
        API_KEY=$(read_config "api_key" "")
        
        case "$PROVIDER" in
            groq) URL="https://api.groq.com/openai/v1/models" ;;
            mistral) URL="https://api.mistral.ai/v1/models" ;;
            openrouter) URL="https://openrouter.ai/api/v1/auth/key" ;;
            openai) URL="https://api.openai.com/v1/models" ;;
            ollama-cloud) URL="https://api.ollama.com/api/tags" ;;
            gemini) URL="https://generativelanguage.googleapis.com/v1beta/models?key=${API_KEY}" ;;
        esac
        
        if [ "$PROVIDER" = "gemini" ]; then
            HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$URL" 2>/dev/null)
        else
            HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$URL" \
                -H "Authorization: Bearer $API_KEY" 2>/dev/null)
        fi
        
        if [ "$HTTP_CODE" = "200" ]; then
            echo "HEALTH: OK — $PROVIDER API reachable (HTTP 200)"
        else
            echo "HEALTH: FAIL — $PROVIDER returned HTTP $HTTP_CODE"
            exit 1
        fi
        ;;
    
    *)
        echo "HEALTH: UNKNOWN provider '$PROVIDER'"
        exit 1
        ;;
esac
