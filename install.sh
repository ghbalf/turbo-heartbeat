#!/usr/bin/env bash
# Turbo-Heartbeat Installer
# Installs to ~/.local/share/turbo-heartbeat/ and sets up a cron job.
#
# Usage:
#   bash install.sh              # Interactive install
#   bash install.sh --uninstall  # Remove installation + cron
#
# This is NOT an OpenClaw skill. It's a standalone cron service.

set -euo pipefail

# ── Config ──────────────────────────────────────────────
INSTALL_DIR="${TURBO_HEARTBEAT_DIR:-$HOME/.local/share/turbo-heartbeat}"
CRON_TAG="# turbo-heartbeat"
SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Colors ──────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

info()  { echo -e "${BLUE}ℹ${NC} $*"; }
ok()    { echo -e "${GREEN}✅${NC} $*"; }
warn()  { echo -e "${YELLOW}⚠${NC} $*"; }
err()   { echo -e "${RED}❌${NC} $*"; }

# ── Uninstall ───────────────────────────────────────────
if [[ "${1:-}" == "--uninstall" ]]; then
    echo -e "\n${YELLOW}🗑  Uninstalling Turbo-Heartbeat${NC}\n"

    # Remove cron entry
    if crontab -l 2>/dev/null | grep -q "$CRON_TAG"; then
        crontab -l | grep -v "$CRON_TAG" | crontab -
        ok "Cron job removed"
    else
        info "No cron job found"
    fi

    # Remove install dir
    if [[ -d "$INSTALL_DIR" ]]; then
        read -rp "Remove $INSTALL_DIR? [y/N] " yn
        if [[ "$yn" =~ ^[Yy] ]]; then
            rm -rf "$INSTALL_DIR"
            ok "Installation removed"
        else
            info "Kept $INSTALL_DIR"
        fi
    else
        info "Install directory not found"
    fi

    echo -e "\n${GREEN}Done.${NC}"
    exit 0
fi

# ── Pre-flight checks ──────────────────────────────────
echo -e "\n${BLUE}🫀 Turbo-Heartbeat Installer${NC}"
echo -e "   Standalone cron service for OpenClaw heartbeat triage\n"

MISSING=()
for cmd in bash curl jq; do
    command -v "$cmd" &>/dev/null || MISSING+=("$cmd")
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
    err "Missing required tools: ${MISSING[*]}"
    echo "   Install them first, then re-run."
    exit 1
fi
ok "Dependencies: bash, curl, jq"

# Check for Ollama
OLLAMA_AVAILABLE=false
if command -v ollama &>/dev/null || curl -sf http://localhost:11434/api/tags &>/dev/null; then
    OLLAMA_AVAILABLE=true
    ok "Ollama detected"
else
    warn "Ollama not found — you'll need a remote triage model (Groq, Gemini, etc.)"
fi

# ── Install files ───────────────────────────────────────
echo ""
info "Installing to: $INSTALL_DIR"

mkdir -p "$INSTALL_DIR"/{scripts/signals,templates,stats}

# Copy runtime files only (no docs, tests, .git)
for f in scripts/detect-env.sh scripts/triage.sh scripts/escalate.sh \
         scripts/notify-critical.sh scripts/health-check.sh \
         scripts/signals/system.sh scripts/signals/email_imap.sh \
         scripts/signals/calendar.sh templates/triage-prompt.md \
         config.example.yaml README.md LICENSE; do
    if [[ -f "$SOURCE_DIR/$f" ]]; then
        cp "$SOURCE_DIR/$f" "$INSTALL_DIR/$f"
    fi
done

chmod +x "$INSTALL_DIR"/scripts/*.sh "$INSTALL_DIR"/scripts/signals/*.sh 2>/dev/null || true

ok "Files installed"

# ── Config ──────────────────────────────────────────────
if [[ -f "$INSTALL_DIR/config.yaml" ]]; then
    info "Existing config.yaml found — keeping it"
else
    cp "$INSTALL_DIR/config.example.yaml" "$INSTALL_DIR/config.yaml"
    warn "Created config.yaml from example — edit it before running!"
    echo ""
    echo "   Key settings to change:"
    echo "     - api_base / api_key / model  (your triage model)"
    echo "     - email_credentials           (path to IMAP creds JSON)"
    echo "     - gateway_token               (your OpenClaw gateway token)"
    echo "     - notify_email / smtp_*       (for critical alerts)"
    echo ""
    echo "   Config location: $INSTALL_DIR/config.yaml"
fi

# ── Cron setup ──────────────────────────────────────────
echo ""
INTERVAL_SEC=60
if [[ "$OLLAMA_AVAILABLE" == "true" ]]; then
    DEFAULT_INTERVAL="1"
    info "Recommended interval: every 1 minute (local model)"
else
    DEFAULT_INTERVAL="5"
    info "Recommended interval: every 5 minutes (remote model, avoid rate limits)"
fi

read -rp "Cron interval in minutes [$DEFAULT_INTERVAL]: " user_interval
INTERVAL_MIN="${user_interval:-$DEFAULT_INTERVAL}"

# Remove old cron entry if exists
EXISTING_CRON=$(crontab -l 2>/dev/null || true)
NEW_CRON=$(echo "$EXISTING_CRON" | grep -v "$CRON_TAG" || true)

CRON_LINE="*/$INTERVAL_MIN * * * * cd $INSTALL_DIR && bash scripts/triage.sh >> stats/triage.log 2>&1 $CRON_TAG"

# Handle every-minute case
if [[ "$INTERVAL_MIN" == "1" ]]; then
    CRON_LINE="* * * * * cd $INSTALL_DIR && bash scripts/triage.sh >> stats/triage.log 2>&1 $CRON_TAG"
fi

echo "$NEW_CRON"$'\n'"$CRON_LINE" | crontab -
ok "Cron job installed (every ${INTERVAL_MIN}min)"

# ── Test run ────────────────────────────────────────────
echo ""
info "Running test triage..."
if cd "$INSTALL_DIR" && bash scripts/triage.sh 2>&1; then
    ok "Test passed"
else
    warn "Test failed — check config.yaml and try: cd $INSTALL_DIR && bash scripts/triage.sh"
fi

# ── Summary ─────────────────────────────────────────────
echo ""
echo -e "${GREEN}═══════════════════════════════════════${NC}"
echo -e "${GREEN}  Turbo-Heartbeat installed! 🫀${NC}"
echo -e "${GREEN}═══════════════════════════════════════${NC}"
echo ""
echo "  Location:  $INSTALL_DIR"
echo "  Config:    $INSTALL_DIR/config.yaml"
echo "  Logs:      $INSTALL_DIR/stats/triage.log"
echo "  Interval:  every ${INTERVAL_MIN} minute(s)"
echo ""
echo "  Commands:"
echo "    Edit config:    nano $INSTALL_DIR/config.yaml"
echo "    View logs:      tail -f $INSTALL_DIR/stats/triage.log"
echo "    Test manually:  cd $INSTALL_DIR && bash scripts/triage.sh"
echo "    Uninstall:      bash $SOURCE_DIR/install.sh --uninstall"
echo ""
