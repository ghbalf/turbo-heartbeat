#!/bin/bash
# Signal Collector: Calendar (gcalcli)
# Checks for upcoming calendar events
# Requires: gcalcli configured and authenticated

set -euo pipefail

# Ensure ~/.local/bin is in PATH (cron has minimal PATH)
export PATH="$HOME/.local/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG="$SKILL_DIR/config.yaml"

# Read config
read_config() {
    local key="$1"
    local default="$2"
    grep -oP "^\s*${key}:\s*\K.*" "$CONFIG" 2>/dev/null | tr -d '"' || echo "$default"
}

HORIZON_MINUTES=$(read_config "calendar_horizon_minutes" "120")

# Check if gcalcli is available
if ! command -v gcalcli &>/dev/null; then
    echo "CALENDAR: ERROR — gcalcli not installed"
    exit 1
fi

# Get events in the next N minutes
NOW=$(date '+%Y-%m-%dT%H:%M:%S')
END=$(date -d "+${HORIZON_MINUTES} minutes" '+%Y-%m-%dT%H:%M:%S' 2>/dev/null || \
     date -v+${HORIZON_MINUTES}M '+%Y-%m-%dT%H:%M:%S' 2>/dev/null)

# gcalcli agenda with TSV output for parsing
EVENTS=$(gcalcli agenda "$NOW" "$END" --tsv 2>/dev/null | grep -v "^$" || echo "")

if [ -z "$EVENTS" ]; then
    echo "CALENDAR: OK"
    exit 0
fi

# Parse events and find the nearest one
NEAREST_TITLE=""
NEAREST_MINUTES=999999

while IFS=$'\t' read -r start_date start_time end_date end_time title location; do
    [ -z "$start_date" ] && continue
    [ "$start_date" = "start_date" ] && continue  # Skip header
    
    # Calculate minutes until event
    EVENT_TS=$(date -d "$start_date $start_time" +%s 2>/dev/null || echo "0")
    NOW_TS=$(date +%s)
    
    if [ "$EVENT_TS" -gt 0 ]; then
        DIFF_MIN=$(( (EVENT_TS - NOW_TS) / 60 ))
        
        if [ "$DIFF_MIN" -ge 0 ] && [ "$DIFF_MIN" -lt "$NEAREST_MINUTES" ]; then
            NEAREST_MINUTES=$DIFF_MIN
            NEAREST_TITLE="$title"
        fi
    fi
done <<< "$EVENTS"

if [ "$NEAREST_MINUTES" -lt 999999 ] && [ -n "$NEAREST_TITLE" ]; then
    # Truncate title
    NEAREST_TITLE="${NEAREST_TITLE:0:50}"
    
    if [ "$NEAREST_MINUTES" -le 30 ]; then
        echo "CALENDAR: \"$NEAREST_TITLE\" in $NEAREST_MINUTES minutes"
    elif [ "$NEAREST_MINUTES" -le 60 ]; then
        echo "CALENDAR: \"$NEAREST_TITLE\" in about 1 hour"
    else
        HOURS=$(( NEAREST_MINUTES / 60 ))
        echo "CALENDAR: \"$NEAREST_TITLE\" in about $HOURS hours"
    fi
else
    echo "CALENDAR: OK"
fi
