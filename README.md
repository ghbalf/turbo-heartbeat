# 🫀 Turbo-Heartbeat

**Fast, cost-effective heartbeat triage for [OpenClaw](https://github.com/openclaw/openclaw).**

Reduces reaction time from ~30 minutes to 30–60 seconds while cutting cloud token costs by 70–90%.

> ⚠️ **This is NOT an OpenClaw skill.** It's a standalone service that runs via system cron
> alongside OpenClaw. It does not use SKILL.md and is not installed through ClawHub.
> See [Installation](#installation) below.

---

## The Problem

OpenClaw's built-in heartbeat uses your main model (e.g. Claude Opus) for every poll. At ~30 minute intervals, that's workable — but:

- Every heartbeat burns tokens, even when the answer is just "HEARTBEAT_OK"
- 30-minute intervals mean up to 30 minutes before you react to urgent events
- Shorter intervals would be great, but unaffordable with cloud models

## The Solution

A dedicated **triage model** acts as a fast dispatcher. It checks for important events every 30 seconds to 6 minutes and only escalates to your main (expensive) model when something actually needs attention.

```
  ⚡ Triage Timer (30s–6min)
       │
  ┌────▼────────────┐
  │ Signal Collectors│  email · calendar · system · custom
  └────┬────────────┘
       │
  ┌────▼───────────────┐
  │ Triage Model       │  (local Ollama or cheap cloud)
  │ "Is this urgent?"  │
  └────┬───────────────┘
       │
  ┌────▼──────┐  ┌────────┐  ┌────┐
  │ ESCALATE  │  │ DEFER  │  │ OK │
  │ → Wake    │  │ → Wait │  │    │
  │   main    │  │        │  │    │
  └───────────┘  └────────┘  └────┘
```

## Deployment Profiles

| Profile | Triage Model | Interval | Cost | Best For |
|---------|-------------|----------|------|----------|
| **A: Local** | Ollama (gemma3:4b, phi4-mini, etc.) | 30–60s | **$0** | Servers, desktops |
| **B: Remote** | Cloud free-tier (Groq, Gemini) | 5–6 min | ~$0 | Laptops without Ollama |
| **C: Ultra-Low** | FunctionGemma (270M) via Ollama | 60s | **$0** | Raspberry Pi, edge |
| **D: Hybrid** | Local primary + cloud fallback | 30–60s | ~$0 | Maximum reliability |

## Installation

### Prerequisites

- [OpenClaw](https://github.com/openclaw/openclaw) running
- `bash`, `curl`, `jq`
- For Profile A/C/D: [Ollama](https://ollama.ai) with a small model loaded

### From GitHub Release

Download the latest release archive — it contains only the files you need:

```bash
# Download and extract
curl -L https://github.com/ghbalf/turbo-heartbeat/releases/latest/download/turbo-heartbeat.tar.gz | tar xz

# Move to wherever you keep your services
mv turbo-heartbeat /path/to/your/services/

# Copy example config
cd /path/to/your/services/turbo-heartbeat
cp config.example.yaml config.yaml

# Edit config.yaml with your settings (model, interval, credentials, etc.)
nano config.yaml
```

### From Source

```bash
git clone https://github.com/ghbalf/turbo-heartbeat.git
cd turbo-heartbeat
cp config.example.yaml config.yaml
# Edit config.yaml
```

### Setup

1. **Detect your environment:**
   ```bash
   bash scripts/detect-env.sh
   ```
   Outputs JSON with system capabilities — helps you pick a profile.

2. **Edit `config.yaml`** — set your triage model, interval, signal collectors, and credentials.

3. **Add cron entry:**
   ```bash
   # Example: run every 60 seconds
   * * * * * cd /path/to/turbo-heartbeat && bash scripts/triage.sh >> stats/triage.log 2>&1
   ```

4. **Test:**
   ```bash
   bash scripts/triage.sh
   # Should output: OK, DEFER: <reason>, or ESCALATE: <reason>
   ```

## Signal Collectors

Modular scripts in `scripts/signals/` that output one-line status:

| Collector | Monitors | Output Example |
|-----------|----------|----------------|
| `system.sh` | Disk, memory, CPU, services | `SYSTEM: Disk 94% full` |
| `email_imap.sh` | Unread emails via IMAP | `EMAIL: 3 unread (boss@co.com: Q2 Review)` |
| `calendar.sh` | Upcoming events via gcalcli | `CALENDAR: "Standup" in 25 minutes` |
| *Custom* | Anything | Drop executable in `scripts/signals/` |

## Triage Decisions

| Decision | Meaning | Action |
|----------|---------|--------|
| `ESCALATE: <reason>` | Needs attention NOW | Wakes main model via OpenClaw cron wake |
| `DEFER: <reason>` | Notable but can wait | Handled on next regular heartbeat |
| `OK` | Nothing noteworthy | Sleep until next cycle |

## Quiet Hours

During configured quiet hours (default 23:00–08:00):
- Only system-critical collectors run
- Critical issues still escalate + notify the human directly (Telegram/email)

## Benchmarks

Tested on ARM64 (20 cores, 122 GB RAM) with GLM-4.7-Flash as triage:

| Metric | Value |
|--------|-------|
| Test accuracy | **92%** (11/12 scenarios) |
| Average latency | **600ms** |
| Cost per triage | **$0.00** (local) |

See `docs/BENCHMARKS.md` for details.

## Directory Structure

```
turbo-heartbeat/
├── README.md                    # This file
├── config.example.yaml          # Example config (copy to config.yaml)
├── scripts/
│   ├── detect-env.sh            # Environment detection
│   ├── triage.sh                # Main triage engine
│   ├── escalate.sh              # OpenClaw wake event sender
│   ├── notify-critical.sh       # Critical alert → human
│   ├── health-check.sh          # Triage model health monitoring
│   └── signals/                 # Signal collectors (modular)
│       ├── system.sh
│       ├── email_imap.sh
│       └── calendar.sh
├── templates/
│   └── triage-prompt.md         # System prompt for triage model
├── tests/
│   └── test_triage.sh           # Test suite
├── docs/
│   ├── ARCHITECTURE.md
│   └── BENCHMARKS.md
├── stats/                       # Runtime data (gitignored)
└── LICENSE
```

## License

MIT — see [LICENSE](LICENSE)

## Credits

Built by [Siegfried](https://github.com/ghbalf) 🐉 for the [OpenClaw](https://github.com/openclaw/openclaw) ecosystem.
