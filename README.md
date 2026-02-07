# 🫀 Turbo-Heartbeat

**Fast, cost-effective heartbeat triage for OpenClaw.**

Reduces reaction time from ~30 minutes to 30-60 seconds while cutting cloud token costs by 70-90%.

---

## The Problem

OpenClaw's built-in heartbeat uses your main model (e.g. Claude Opus) for every poll. At ~30 minute intervals, that's workable — but:

- Every heartbeat burns tokens, even when the answer is just "HEARTBEAT_OK"
- 30-minute intervals mean up to 30 minutes before you react to urgent events
- Shorter intervals would be great, but unaffordable with cloud models

## The Solution

A dedicated **triage model** acts as a fast dispatcher. It checks for important events every 30 seconds to 6 minutes and only escalates to your main (expensive) model when something actually needs attention.

```
┌─────────────────────────────────────────────────────────┐
│  ⚡ Triage Timer (30s–6min)                              │
│       │                                                  │
│  ┌────▼────────────┐                                     │
│  │ Signal Collectors│ email · calendar · system · custom │
│  └────┬────────────┘                                     │
│       │                                                  │
│  ┌────▼───────────────┐                                  │
│  │ Triage Model       │ (local Ollama or cheap cloud)   │
│  │ "Is this urgent?"  │                                  │
│  └────┬───────────────┘                                  │
│       │                                                  │
│  ┌────▼──────────┐ ┌──────────┐ ┌────────────┐          │
│  │ ESCALATE      │ │ DEFER    │ │ OK         │          │
│  │ → Wake main   │ │ → Wait   │ │ → Sleep    │          │
│  │   model NOW   │ │   for    │ │            │          │
│  └───────────────┘ │   next   │ └────────────┘          │
│                     │   poll   │                          │
│                     └──────────┘                          │
└─────────────────────────────────────────────────────────┘
```

**Result:** Faster reactions at *lower* cost — whether you're running a power server or an old laptop.

## Deployment Profiles

| Profile | Triage Model | Interval | Cost | Best For |
|---------|-------------|----------|------|----------|
| **A: Local** | Ollama (gemma3:4b, phi4-mini, etc.) | 30–60s | **$0** | Servers, desktops |
| **B: Remote** | Cloud free-tier (Groq, Gemini, Ollama Cloud) | 5–6 min | ~$0 | Laptops without Ollama |
| **C: Ultra-Low** | FunctionGemma (270M) via Ollama | 60s | **$0** | Raspberry Pi, edge devices |
| **D: Hybrid** | Local primary + cloud fallback | 30–60s | ~$0 | Maximum reliability |

## Quick Start

> **No manual config editing required.** Ask your OpenClaw assistant:

```
"Set up Turbo-Heartbeat for me"
```

The assistant will:

1. **Detect your environment** — hardware, Ollama, available models
2. **Recommend a profile** — with explanation of trade-offs
3. **Guide model selection** — suggest the best triage model for your setup
4. **Configure interval** — with tested minimums and warnings for aggressive values
5. **Enable signal collectors** — email, calendar, system health, custom
6. **Create the cron job** — integrated with OpenClaw's scheduler
7. **Run a test cycle** — verify everything works end-to-end

That's it. The assistant IS the configuration UI.

## Signal Collectors

Modular scripts that gather status from different sources:

| Collector | Monitors | Output Example |
|-----------|----------|----------------|
| `system.sh` | Disk, memory, CPU, services | `SYSTEM: Disk 94% full` |
| `email_imap.sh` | Unread emails via IMAP | `EMAIL: 3 unread (boss@company.com: Q2 Review)` |
| `calendar.sh` | Upcoming events via gcalcli | `CALENDAR: "Team Standup" in 25 minutes` |
| *Custom* | Anything you want | `CUSTOM: <your signal>` |

**Adding a custom collector:** Drop any executable script into `scripts/signals/` that outputs one line: `NAME: STATUS_TEXT`. The triage script picks it up automatically.

## Triage Decisions

The triage model evaluates all signals and responds with exactly one of:

| Decision | Meaning | Action |
|----------|---------|--------|
| `ESCALATE: <reason>` | Needs attention NOW | Wakes main model immediately |
| `DEFER: <reason>` | Notable but can wait | Handled on next regular heartbeat |
| `OK` | Nothing noteworthy | Sleep until next triage cycle |

## Quiet Hours

During configured quiet hours (default 23:00–08:00):

- Only **system-critical** collectors run (no email/calendar noise)
- If a critical issue is found:
  - Main model is still woken
  - **Human is notified directly** via Telegram/Discord/Signal/email
  - **Remediation guidance** is auto-generated per alert type

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

## Architecture

```
skills/turbo-heartbeat/
├── SKILL.md                     # Skill instructions for OpenClaw
├── README.md                    # This file
├── config.yaml                  # Generated by assistant (don't edit manually)
├── scripts/
│   ├── detect-env.sh            # Environment detection
│   ├── triage.sh                # Main triage engine
│   ├── escalate.sh              # OpenClaw wake event sender
│   ├── notify-critical.sh       # Critical alert → human (quiet hours)
│   ├── health-check.sh          # Triage model health monitoring
│   └── signals/                 # Signal collectors (modular)
│       ├── system.sh            # Disk, memory, processes
│       ├── email_imap.sh        # IMAP unread check
│       └── calendar.sh          # gcalcli upcoming events
├── templates/
│   └── triage-prompt.md         # System prompt for triage model
├── stats/
│   └── triage.log               # Triage result log
├── tests/
│   └── test_triage.sh           # Test suite (12 scenarios)
└── docs/
    ├── ARCHITECTURE.md          # Technical deep-dive
    └── BENCHMARKS.md            # Performance data
```

### Integration with OpenClaw

Turbo-Heartbeat runs as a **hybrid integration**:

- **Fast loop:** System cron runs `triage.sh` every N seconds
- **Regular heartbeat:** OpenClaw's built-in heartbeat remains as a safety net
- **Escalation:** On ESCALATE → wake event triggers the main model immediately

The regular heartbeat catches anything the triage might miss. Belt and suspenders.

#### 💡 Optimizing the OpenClaw Heartbeat

With Turbo-Heartbeat handling fast triage, your OpenClaw heartbeat becomes a **safety net only**. Consider optimizing it to save tokens and money:

| Setting | Without Turbo-HB | With Turbo-HB | Savings |
|---------|-------------------|---------------|---------|
| **Heartbeat interval** | 15–30 min | 60–120 min | 2–8× fewer polls |
| **Heartbeat model** | Main model (Opus, GPT-4) | Cheaper model (Haiku, GPT-4o-mini) | 5–20× cheaper per poll |
| **Combined** | ~$2–7/day | ~$0.10–0.50/day | **90–95% savings** |

**How to adjust** (ask your assistant):

```
"Increase my heartbeat interval to 2 hours"
"Use Haiku for heartbeat checks"
```

Your OpenClaw heartbeat now only needs to:
- Run periodic maintenance tasks
- Catch edge cases the triage might miss
- Serve as a "dead man's switch" if the triage loop stops

It no longer needs to be fast *or* smart — just reliable.

## Recommended Triage Models

### Local (Ollama)

| Model | Params | Size | RAM | Latency* | Notes |
|-------|--------|------|-----|----------|-------|
| **gemma3:4b** | 4B | 2.5 GB | ~4 GB | ~2s | ⭐ Default recommendation |
| phi4-mini | 3.8B | 2.5 GB | ~4 GB | ~2s | Good multilingual support |
| llama3.2:3b | 3B | 2 GB | ~3 GB | ~1.5s | Fast and small |
| **FunctionGemma** | 270M | 180 MB | ~500 MB | <1s | 🏆 For Raspberry Pi / edge |
| glm-4.7-flash | 9B | 5.5 GB | ~8 GB | ~3s | Tested, 92% accuracy |

*Latency on ARM64 without GPU, estimated

### Remote (Free-Tier / Budget)

| Provider | Model | Free Tier | Rate Limit | Notes |
|----------|-------|-----------|------------|-------|
| **Groq** | llama-3.3-70b | Yes | 30 req/min | ⭐ Fast + free |
| **Google** | gemini-2.0-flash | Yes | 15 req/min | Generous free tier |
| Ollama Cloud | Various | Yes (light use) | Usage-based | Same API as local |
| Mistral | mistral-small | Yes | 10 req/min | Good quality |
| Cerebras | llama-3.3-70b | Yes | 30 req/min | Very fast inference |

> **Important:** The triage model MUST use a different provider/model than your main model. Otherwise you're escalating to the same thing you're trying to save on.

## Benchmarks

Tested on ARM64 (20 cores, 122 GB RAM) with GLM-4.7-Flash (9B) as triage model:

| Metric | Value |
|--------|-------|
| Test accuracy | **92%** (11/12 scenarios) |
| Average latency | **600ms** |
| Cost per triage | **$0.00** (local) |
| Estimated daily cost | **$0.00** vs ~$2.40–7.20 with cloud heartbeats |
| Only miss | "Meeting in 3h" classified as OK instead of DEFER (edge case) |

See `docs/BENCHMARKS.md` for detailed numbers.

## Requirements

| Requirement | Profile A (Local) | Profile B (Remote) | Profile C (RPi) |
|-------------|-------------------|--------------------|------------------|
| OpenClaw | v0.40+ | v0.40+ | v0.40+ |
| Ollama | v0.15+ | Not needed | v0.13.5+ |
| Free RAM | 4 GB | 100 MB | 500 MB |
| Free disk | 3 GB | 50 MB | 500 MB |
| Internet | Not needed | Required | Not needed |
| bash, curl, jq | Yes | Yes | Yes |

## Statistics

Triage results are logged automatically. Ask your assistant:

```
"Show me Turbo-Heartbeat stats"
```

Example output:
```
Last 24h: 2880 triage checks, 8 escalations (0.3% rate)
Average latency: 520ms
Cost: $0.00 (local)
Escalation reasons: 5× email, 2× calendar, 1× system
```

## License

MIT — see [LICENSE](LICENSE)

## Credits

Built by [Siegfried](https://github.com/openclaw/turbo-heartbeat) 🐉 for the [OpenClaw](https://github.com/openclaw/openclaw) ecosystem.

---

*"Your heartbeat just got 1800× faster — and costs less."*
