#!/bin/bash
# Signal Collector: Email (IMAP)
# Checks for unread emails via IMAP and returns a summary
# Requires: python3, credentials in config or env

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG="$SKILL_DIR/config.yaml"

# Read config
read_config() {
    local key="$1"
    local default="$2"
    grep -oP "^\s*${key}:\s*\K.*" "$CONFIG" 2>/dev/null | tr -d '"' || echo "$default"
}

# Credentials can come from config, env, or credential files
IMAP_HOST=$(read_config "imap_host" "${IMAP_HOST:-}")
IMAP_PORT=$(read_config "imap_port" "${IMAP_PORT:-993}")
IMAP_USER=$(read_config "imap_user" "${IMAP_USER:-}")
IMAP_PASS=$(read_config "imap_pass" "${IMAP_PASS:-}")
CRED_FILE=$(read_config "email_credentials" "${CRED_FILE:-}")

# Try loading from credential file if direct creds not set
if [ -z "$IMAP_HOST" ] && [ -n "$CRED_FILE" ] && [ -f "$CRED_FILE" ]; then
    IMAP_HOST=$(python3 -c "import json; d=json.load(open('$CRED_FILE')); print(d.get('imap_host',''))" 2>/dev/null)
    IMAP_PORT=$(python3 -c "import json; d=json.load(open('$CRED_FILE')); print(d.get('imap_port',993))" 2>/dev/null)
    IMAP_USER=$(python3 -c "import json; d=json.load(open('$CRED_FILE')); print(d.get('username', d.get('email','')))" 2>/dev/null)
    IMAP_PASS=$(python3 -c "import json; d=json.load(open('$CRED_FILE')); print(d.get('password',''))" 2>/dev/null)
fi

if [ -z "$IMAP_HOST" ] || [ -z "$IMAP_USER" ]; then
    echo "EMAIL: ERROR — no IMAP credentials configured"
    exit 1
fi

# Use Python for IMAP check (fast, reliable)
python3 -c "
import imaplib
import email
from email.header import decode_header
import sys

try:
    # Connect
    mail = imaplib.IMAP4_SSL('${IMAP_HOST}', ${IMAP_PORT})
    mail.login('${IMAP_USER}', '${IMAP_PASS}')
    mail.select('INBOX', readonly=True)
    
    # Search for unseen
    status, messages = mail.search(None, 'UNSEEN')
    if status != 'OK':
        print('EMAIL: ERROR — IMAP search failed')
        sys.exit(1)
    
    msg_ids = messages[0].split()
    count = len(msg_ids)
    
    if count == 0:
        print('EMAIL: OK')
    else:
        # Get summary of most recent unseen (up to 3)
        senders = []
        for msg_id in msg_ids[-3:]:
            status, data = mail.fetch(msg_id, '(BODY.PEEK[HEADER.FIELDS (FROM SUBJECT)])')
            if status == 'OK':
                header = data[0][1].decode('utf-8', errors='replace')
                msg = email.message_from_string(header)
                
                from_raw = msg.get('From', 'unknown')
                subj_raw = msg.get('Subject', 'no subject')
                
                # Decode if encoded
                if subj_raw:
                    decoded = decode_header(subj_raw)
                    subj = ''.join(
                        part.decode(enc or 'utf-8') if isinstance(part, bytes) else part
                        for part, enc in decoded
                    )
                else:
                    subj = 'no subject'
                
                # Extract just the email address or name
                if '<' in from_raw:
                    sender = from_raw.split('<')[0].strip().strip('\"')
                    if not sender:
                        sender = from_raw.split('<')[1].split('>')[0]
                else:
                    sender = from_raw.strip()
                
                # Truncate for triage (keep it short)
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
