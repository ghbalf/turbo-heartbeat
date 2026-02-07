#!/bin/bash
# Signal Collector: Email (IMAP)
# Checks for unread emails via IMAP and returns a summary
#
# Credentials are loaded via Secret Store (preferred) or credential files.
# The secret values are NEVER exposed to the LLM — only used at runtime.
#
# Secret Store keys: EMAIL_USER, EMAIL_PASSWORD
# Or: credential file path in config.yaml → email_credentials

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG="$SKILL_DIR/config.yaml"
SECRET_STORE="${HOME}/.openclaw/workspace/scripts/secret-store.sh"

# Read config
read_config() {
    local key="$1" default="$2"
    grep -oP "^\s*${key}:\s*\K.*" "$CONFIG" 2>/dev/null | tr -d '"' || echo "$default"
}

IMAP_HOST=$(read_config "imap_host" "imap.strato.de")
IMAP_PORT=$(read_config "imap_port" "993")
CRED_FILE=$(read_config "email_credentials" "")

# Load credentials — Secret Store first, then credential file
IMAP_USER=""
IMAP_PASS=""

if [ -x "$SECRET_STORE" ]; then
    IMAP_USER=$(bash "$SECRET_STORE" get EMAIL_USER 2>/dev/null || true)
    IMAP_PASS=$(bash "$SECRET_STORE" get EMAIL_PASSWORD 2>/dev/null || true)
fi

# Fallback to credential file if Secret Store doesn't have them
if [ -z "$IMAP_USER" ] && [ -n "$CRED_FILE" ] && [ -f "$CRED_FILE" ]; then
    IMAP_USER=$(python3 -c "import json; d=json.load(open('$CRED_FILE')); print(d.get('username', d.get('email','')))" 2>/dev/null)
    IMAP_PASS=$(python3 -c "import json; d=json.load(open('$CRED_FILE')); print(d.get('password',''))" 2>/dev/null)
fi

if [ -z "$IMAP_HOST" ] || [ -z "$IMAP_USER" ]; then
    echo "EMAIL: ERROR — no IMAP credentials configured"
    exit 1
fi

# Pass credentials via environment variables (not inline in code!)
export _IMAP_HOST="$IMAP_HOST"
export _IMAP_PORT="$IMAP_PORT"
export _IMAP_USER="$IMAP_USER"
export _IMAP_PASS="$IMAP_PASS"

python3 -c "
import imaplib
import email
from email.header import decode_header
import os, sys

try:
    host = os.environ['_IMAP_HOST']
    port = int(os.environ['_IMAP_PORT'])
    user = os.environ['_IMAP_USER']
    passwd = os.environ['_IMAP_PASS']
    
    mail = imaplib.IMAP4_SSL(host, port)
    mail.login(user, passwd)
    mail.select('INBOX', readonly=True)
    
    status, messages = mail.search(None, 'UNSEEN')
    if status != 'OK':
        print('EMAIL: ERROR — IMAP search failed')
        sys.exit(1)
    
    msg_ids = messages[0].split()
    count = len(msg_ids)
    
    if count == 0:
        print('EMAIL: OK')
    else:
        senders = []
        for msg_id in msg_ids[-3:]:
            status, data = mail.fetch(msg_id, '(BODY.PEEK[HEADER.FIELDS (FROM SUBJECT)])')
            if status == 'OK':
                header = data[0][1].decode('utf-8', errors='replace')
                msg = email.message_from_string(header)
                
                from_raw = msg.get('From', 'unknown')
                subj_raw = msg.get('Subject', 'no subject')
                
                if subj_raw:
                    decoded = decode_header(subj_raw)
                    subj = ''.join(
                        part.decode(enc or 'utf-8') if isinstance(part, bytes) else part
                        for part, enc in decoded
                    )
                else:
                    subj = 'no subject'
                
                if '<' in from_raw:
                    sender = from_raw.split('<')[0].strip().strip('\"')
                    if not sender:
                        sender = from_raw.split('<')[1].split('>')[0]
                else:
                    sender = from_raw.strip()
                
                sender = sender[:30]
                subj = subj[:40]
                senders.append(f'{sender}: {subj}')
        
        summary = '; '.join(senders)
        print(f'EMAIL: {count} unread ({summary})')
    
    mail.logout()

except imaplib.IMAP4.error as e:
    print(f'EMAIL: ERROR — IMAP: {e}')
except Exception as e:
    print(f'EMAIL: ERROR — {e}')
" 2>&1

# Clean up environment
unset _IMAP_HOST _IMAP_PORT _IMAP_USER _IMAP_PASS
