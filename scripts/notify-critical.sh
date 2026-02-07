#!/bin/bash
# Turbo-Heartbeat: Critical Notification
# Sends urgent notification to human via channel AND/OR email
# Used during quiet hours for system-critical events
#
# Usage: notify-critical.sh "<alert>" "<guidance>"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG="$SKILL_DIR/config.yaml"

ALERT="${1:-System critical alert}"
GUIDANCE="${2:-Please check your system as soon as possible.}"

# Read config
read_config() {
    local key="$1"
    local default="$2"
    grep -oP "^\s*${key}:\s*\K.*" "$CONFIG" 2>/dev/null | tr -d '"' || echo "$default"
}

NOTIFY_CHANNEL=$(read_config "notify_channel" "")
NOTIFY_EMAIL=$(read_config "notify_email" "")
SMTP_HOST=$(read_config "smtp_host" "")
SMTP_PORT=$(read_config "smtp_port" "465")
SMTP_USER=$(read_config "smtp_user" "")
SMTP_PASS=$(read_config "smtp_pass" "")
SMTP_FROM=$(read_config "smtp_from" "")

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S %Z')
HOSTNAME=$(hostname)

# Format the notification message
MESSAGE="🚨 CRITICAL SYSTEM ALERT — ${HOSTNAME}

Time: ${TIMESTAMP}
Alert: ${ALERT}

What to do:
${GUIDANCE}

---
This is an automated alert from Turbo-Heartbeat.
Your assistant is in quiet hours but this alert was too critical to delay."

NOTIFIED=false

# Notify via OpenClaw channel (Telegram, Discord, Signal, etc.)
if [ -n "$NOTIFY_CHANNEL" ]; then
    GATEWAY_PORT=$(read_config "gateway_port" "3000")
    GATEWAY_TOKEN=$(read_config "gateway_token" "")
    
    if [ -z "$GATEWAY_TOKEN" ] && [ -f "$HOME/.openclaw/config.yaml" ]; then
        GATEWAY_TOKEN=$(grep -oP 'token:\s*\K\S+' "$HOME/.openclaw/config.yaml" 2>/dev/null || echo "")
    fi
    
    if [ -n "$GATEWAY_TOKEN" ]; then
        # Use OpenClaw message API to send to configured channel
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
            "http://localhost:${GATEWAY_PORT}/api/message" \
            -H "Authorization: Bearer ${GATEWAY_TOKEN}" \
            -H "Content-Type: application/json" \
            -d "{
                \"channel\": \"${NOTIFY_CHANNEL}\",
                \"message\": $(echo "$MESSAGE" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))')
            }" 2>/dev/null || echo "000")
        
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "204" ]; then
            echo "NOTIFY: Sent via channel '$NOTIFY_CHANNEL' (HTTP $HTTP_CODE)"
            NOTIFIED=true
        else
            echo "NOTIFY: Channel '$NOTIFY_CHANNEL' failed (HTTP $HTTP_CODE)" >&2
        fi
    fi
fi

# Notify via email
if [ -n "$NOTIFY_EMAIL" ] && [ -n "$SMTP_HOST" ]; then
    SUBJECT="🚨 CRITICAL: ${ALERT} — ${HOSTNAME}"
    
    # Send via Python (more reliable than sendmail)
    python3 -c "
import smtplib
from email.mime.text import MIMEText

msg = MIMEText('''${MESSAGE}''')
msg['Subject'] = '''${SUBJECT}'''
msg['From'] = '${SMTP_FROM}'
msg['To'] = '${NOTIFY_EMAIL}'

try:
    with smtplib.SMTP_SSL('${SMTP_HOST}', ${SMTP_PORT}) as s:
        s.login('${SMTP_USER}', '${SMTP_PASS}')
        s.send_message(msg)
    print('Email sent successfully')
except Exception as e:
    print(f'Email failed: {e}')
" 2>&1

    NOTIFIED=true
    echo "NOTIFY: Email sent to $NOTIFY_EMAIL"
fi

# Fallback: write to local alert file if nothing else worked
if [ "$NOTIFIED" = false ]; then
    ALERT_FILE="$SKILL_DIR/stats/CRITICAL_ALERTS.txt"
    echo "[$TIMESTAMP] $ALERT — $GUIDANCE" >> "$ALERT_FILE"
    echo "NOTIFY: No channel/email configured. Written to $ALERT_FILE" >&2
    echo "NOTIFY: Configure 'notify_channel' and/or 'notify_email' in config.yaml" >&2
fi
