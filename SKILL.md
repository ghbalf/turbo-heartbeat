# Turbo-Heartbeat Skill

> Fast, cost-effective heartbeat triage using a dedicated lightweight model.
> Reduces reaction time from ~30 minutes to 30-60 seconds while cutting cloud token costs by 70-90%.

## Overview

Turbo-Heartbeat adds a fast triage layer between OpenClaw's heartbeat timer and your main (expensive) model. A small, dedicated triage model checks for important events every 30 seconds to 6 minutes and only escalates to your main model when something actually needs attention.

## How It Works

1. **Triage Timer** fires every N seconds (configurable)
2. **Signal Collectors** gather status from email, calendar, system health, etc.
3. **Triage Model** (local or remote) evaluates: "Is this important?"
4. **Decision:**
   - `ESCALATE` → Wake the main model via OpenClaw cron wake
   - `DEFER` → Not urgent, handle on next regular heartbeat
   - `OK` → Nothing to do

## Deployment Profiles

| Profile | Triage Model | Interval | Cost | Best For |
|---------|-------------|----------|------|----------|
| **A: Local** | Ollama (gemma3:4b, phi4-mini) | 30-60s | $0 | Servers, desktops |
| **B: Remote** | Cloud free-tier (Groq, Gemini, Ollama Cloud) | 5-6 min | ~$0 | Old laptops, no Ollama |
| **C: Ultra-Low** | FunctionGemma (270M) via Ollama | 60s | $0 | Raspberry Pi, edge |
| **D: Hybrid** | Local primary + cloud fallback | 30-60s | ~$0 | Maximum reliability |

## Setup (Assistant-Guided)

**Do not edit config.yaml manually.** When a user wants to set up Turbo-Heartbeat:

### Init Phase

Run the environment detection script first:

```bash
bash <skill_dir>/scripts/detect-env.sh
```

This outputs JSON with system capabilities. Use it to recommend a profile.

**Step-by-step guided setup:**

1. **Detect environment** — Run `detect-env.sh`, read output
2. **Recommend profile** — Based on detected capabilities:
   - Ollama installed + enough RAM → Profile A (local)
   - Ollama installed + low RAM (RPi) → Profile C (ultra-low, FunctionGemma)
   - No Ollama → Profile B (remote, need API key for second provider)
   - Ollama + API key → Profile D (hybrid)
3. **Explain the recommendation** — Tell the user WHY this profile, what trade-offs
4. **Select triage model** — Suggest best model for their hardware/plan
5. **Configure interval** — Suggest tested minimum (see below), accept user's choice
6. **Enable signal collectors** — Ask which events to monitor
7. **Write config** — Generate `config.yaml` in skill directory
8. **Create cron job** — Set up OpenClaw cron for triage loop
9. **Test** — Run one triage cycle, show result

### Interval Policy

Suggest tested minimum intervals. Accept larger or equal values without comment. If user wants smaller:

1. **Warn once** with explanation (CPU load, rate limits, overlap risk)
2. **If user insists** → Accept and log the warning:
   ```yaml
   # Append to config.yaml warnings_log
   - timestamp: "<ISO-8601>"
     setting: "interval_seconds"
     recommended: <minimum>
     chosen: <user_value>
     reason: "<explanation>"
   ```
3. **On future problems** → Reference the logged warning with date

**Tested minimums:**

| Profile | Minimum | Reason |
|---------|---------|--------|
| A (Local) | 30s | CPU/model latency |
| B (Remote) | 300s (5 min) | Free-tier rate limits |
| C (Ultra-Low) | 60s | RPi CPU constraints |
| D (Hybrid) | 30s | Same as local primary |

### Reconfiguration

Users can change settings anytime by asking. The assistant:
- Reads current `config.yaml`
- Explains current settings
- Suggests changes with trade-off explanation
- Updates config and restarts cron job

## Triage Prompt

The triage model receives signal collector output and must respond with exactly one of:

```
ESCALATE: <reason>
DEFER: <reason>
OK
```

Use the template at `<skill_dir>/templates/triage-prompt.md` as system prompt.

## Signal Collectors

Each collector is an executable script in `<skill_dir>/scripts/signals/` that outputs a one-line status:

```
SIGNAL_NAME: STATUS_TEXT
```

Examples:
- `EMAIL: 3 unread` → might escalate
- `EMAIL: OK` → no action
- `CALENDAR: Meeting "Standup" in 25 minutes` → escalate
- `SYSTEM: Disk 94% full` → escalate
- `SYSTEM: OK` → no action

### Available Collectors

| Collector | File | Requires |
|-----------|------|----------|
| System health | `signals/system.sh` | None (built-in) |
| Email (IMAP) | `signals/email_imap.sh` | IMAP credentials |
| Calendar | `signals/calendar.sh` | gcalcli |
| Custom | User-defined | Varies |

## Escalation

On ESCALATE, the skill sends a wake event to OpenClaw:

```bash
bash <skill_dir>/scripts/escalate.sh "<reason>"
```

This uses the OpenClaw cron wake API to immediately trigger the main model.

## Critical Notifications (Quiet Hours)

During quiet hours, only system-critical signals are checked. If a critical issue is found:

1. **ESCALATE** still fires (wakes the main model)
2. **Human is notified directly** via configured channel and/or email
3. **Guidance is included** — what happened, what to do, how to fix it

Configure in `config.yaml` (set by assistant during init):

```yaml
# Notification settings for critical alerts
notify_channel: "telegram"           # OpenClaw channel to use
notify_email: "user@example.com"     # Email for critical alerts
smtp_host: "smtp.example.com"        # SMTP server
smtp_port: 465                       # SMTP port (SSL)
smtp_user: "sender@example.com"      # SMTP login
smtp_pass: ""                        # SMTP password (or use env var)
smtp_from: "assistant@example.com"   # From address
```

Example notification:
```
🚨 CRITICAL SYSTEM ALERT — myserver

Time: 2026-02-07 03:15:00 CET
Alert: disk 94% full

What to do:
Disk usage is critical. Run 'df -h' to check. Consider removing
old logs/files or expanding storage. If the system becomes
unresponsive, you may need to SSH in and free space manually.
```

The guidance is auto-generated based on the alert type (disk, memory, Ollama down, gateway down, etc.). The assistant can customize guidance templates during setup.

## Health Check

`scripts/health-check.sh` verifies the triage model is responsive. Run periodically (every 10 triage cycles). On failure:
- Profile A/C: Try to restart Ollama
- Profile B: Log error, skip triage
- Profile D: Switch to cloud fallback

## Statistics

Triage results are logged to `<skill_dir>/stats/triage.log`:

```
2026-02-07T12:30:00+01:00 OK signals=3 latency_ms=450
2026-02-07T12:30:30+01:00 ESCALATE reason="EMAIL: 2 unread from boss" latency_ms=520
```

The assistant can summarize stats on request:
- Total triage checks (24h/7d/30d)
- Escalation count and rate
- Average latency
- False positive rate (if user provides feedback)

## Files

```
skills/turbo-heartbeat/
├── SKILL.md                    # This file
├── README.md                   # GitHub/ClawHub README
├── config.yaml                 # Generated by assistant (do not edit manually)
├── scripts/
│   ├── detect-env.sh           # Environment detection
│   ├── triage.sh               # Main triage loop
│   ├── escalate.sh             # Wake event sender
│   ├── notify-critical.sh      # Critical alert to human (quiet hours)
│   ├── health-check.sh         # Triage model health
│   └── signals/                # Signal collectors
│       ├── system.sh           # Disk, memory, processes
│       ├── email_imap.sh       # IMAP unread check
│       └── calendar.sh         # gcalcli next events
├── templates/
│   └── triage-prompt.md        # System prompt for triage model
├── stats/
│   └── triage.log              # Triage result log
└── docs/
    ├── ARCHITECTURE.md         # Technical details
    └── BENCHMARKS.md           # Performance data
```
