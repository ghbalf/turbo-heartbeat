# Turbo-Heartbeat Architecture

## Overview

Turbo-Heartbeat is a triage layer that sits between OpenClaw's heartbeat timer and the main (expensive) cloud model. It uses a dedicated lightweight model to evaluate signals and decide whether the main model needs to wake up.

## Component Diagram

```
                    ┌─────────────────────────┐
                    │    OpenClaw Gateway      │
                    │  ┌───────────────────┐   │
                    │  │ Cron Scheduler    │   │
                    │  │  - Triage job     │───┼──── Every 30s-6min
                    │  │  - Regular HB     │   │     (configurable)
                    │  └───────────────────┘   │
                    │  ┌───────────────────┐   │
                    │  │ Wake API          │◄──┼──── escalate.sh
                    │  │ /api/cron/wake    │   │
                    │  └───────────────────┘   │
                    └─────────────────────────┘
                              │
               ┌──────────────▼──────────────┐
               │        triage.sh            │
               │                             │
               │  1. Check quiet hours       │
               │  2. Check cooldown          │
               │  3. Run signal collectors   │
               │  4. Call triage model       │
               │  5. Act on decision         │
               └──────────────┬──────────────┘
                              │
           ┌──────────────────┼──────────────────┐
           │                  │                  │
    ┌──────▼──────┐   ┌──────▼──────┐   ┌──────▼──────┐
    │ system.sh   │   │ email.sh    │   │calendar.sh  │
    │ Disk/RAM/   │   │ IMAP UNSEEN │   │ gcalcli     │
    │ CPU/Procs   │   │ count +     │   │ upcoming    │
    │             │   │ summaries   │   │ events      │
    └──────┬──────┘   └──────┬──────┘   └──────┬──────┘
           │                  │                  │
           └──────────────────┼──────────────────┘
                              │
                    ┌─────────▼─────────┐
                    │  Triage Model     │
                    │  (Ollama / Cloud) │
                    │                   │
                    │  Input: Signals   │
                    │  Output: One of:  │
                    │  - ESCALATE: ...  │
                    │  - DEFER: ...     │
                    │  - OK             │
                    └─────────┬─────────┘
                              │
              ┌───────────────┼───────────────┐
              │               │               │
       ┌──────▼──────┐ ┌─────▼─────┐ ┌──────▼──────┐
       │ ESCALATE    │ │ DEFER     │ │ OK          │
       │             │ │           │ │             │
       │ escalate.sh │ │ Log only  │ │ Log only    │
       │ → wake API  │ │ Wait for  │ │ Sleep until │
       │             │ │ next HB   │ │ next cycle  │
       │ If quiet:   │ └───────────┘ └─────────────┘
       │ notify.sh   │
       │ → human     │
       └─────────────┘
```

## Data Flow

### 1. Signal Collection

Each signal collector is an independent bash script in `scripts/signals/`. They follow a strict contract:

**Input:** None (collectors read their own config/credentials)
**Output:** Exactly one line: `SIGNAL_NAME: STATUS_TEXT`
**Exit code:** 0 on success, non-zero on error (output becomes `NAME: ERROR`)

Example outputs:
```
SYSTEM: OK
EMAIL: 2 unread (boss@corp.com: "Q2 Review due today")
CALENDAR: "Team Standup" in 25 minutes
SYSTEM: Disk 94% full on /
```

Collectors run sequentially (fast enough at <100ms each). During quiet hours, only `system.sh` runs.

### 2. Triage Model Call

The collected signals are concatenated and sent to the triage model with a minimal system prompt (`templates/triage-prompt.md`). The prompt instructs the model to output exactly one line:

```
ESCALATE: <brief reason>
DEFER: <brief reason>
OK
```

**Local mode (Ollama):** Piped via `ollama run <model>`. Uses `think: false` for models that support it (like GLM-4.7-Flash) to avoid wasting tokens on internal reasoning.

**Remote mode (Cloud API):** Standard OpenAI-compatible chat completions endpoint. Temperature 0.1, max_tokens 50.

### 3. Decision Handling

| Decision | Action | Log Entry |
|----------|--------|-----------|
| `ESCALATE` | Run `escalate.sh` → OpenClaw wake API | Timestamp, reason, latency |
| `DEFER` | Nothing (wait for next regular heartbeat) | Timestamp, reason, latency |
| `OK` | Nothing | Timestamp, latency |
| Unknown | Log as anomaly | Timestamp, raw decision, latency |

### 4. Escalation

`escalate.sh` sends a POST to OpenClaw's `/api/cron/wake` endpoint with:
- `text`: `[Turbo-HB] <reason>` — appears as a system event in the main session
- `mode`: `now` — triggers the main model immediately

The main model receives the wake event as context and can act on the reason (e.g., "2 urgent emails from boss" → check and summarize emails).

### 5. Quiet Hours + Critical Notifications

During quiet hours (configurable, default 23:00–08:00):

1. Only `system.sh` runs (skip email/calendar noise)
2. If `system.sh` finds a critical issue:
   - `escalate.sh` fires (wake main model)
   - `notify-critical.sh` fires (alert human directly)
3. `notify-critical.sh` tries three channels in order:
   - **OpenClaw channel** (Telegram, Discord, etc.) via message API
   - **Email** via SMTP
   - **Local file** as fallback if both fail

Auto-generated guidance is included based on the alert type (disk full, memory critical, Ollama down, gateway down).

## Cooldown & Rate Limiting

To prevent escalation storms:

- **Cooldown:** Minimum time between escalations (default: 300s / 5 min)
- **Tracked via:** `stats/.last_escalation` file (Unix timestamp)
- **If in cooldown:** Log as `OK cooldown=Ns/300s` and skip

The `max_per_hour` config (default: 6) is enforced by the OpenClaw cron scheduler.

## Health Monitoring

`health-check.sh` verifies the triage model is responsive. Run every 10th triage cycle or on demand.

**Local (Ollama):**
1. Check if Ollama API responds (`/api/tags`)
2. Run a quick inference test ("Say OK")
3. On failure: attempt `systemctl restart ollama`

**Remote (Cloud):**
1. Check if provider API returns HTTP 200 (models endpoint)
2. On failure: log error

**Profile D (Hybrid):**
- If local health check fails → switch to cloud fallback
- Continue checking local health periodically → switch back when recovered

## Security Considerations

### Triage Model Only Sees Metadata

The triage model receives only signal summaries, never full email content or calendar details. Example:

```
EMAIL: 2 unread (sender@example.com: "Subject line")
```

Not:
```
EMAIL: Full email body with sensitive content...
```

This minimizes data exposure to the triage model, which may be a small local model with weaker safety guardrails.

### Prompt Injection Surface

The triage model's input comes from signal collectors, which read from:
- IMAP (email subjects/senders — attacker-controlled)
- Calendar (event names — potentially shared)
- System metrics (not attacker-controlled)

Mitigations:
- Triage prompt is strict: "respond with exactly one line"
- `max_tokens: 50` limits response length
- Output is pattern-matched (`ESCALATE:/DEFER:/OK`), not executed
- Unrecognized output is logged as `UNKNOWN`, not acted upon

### Credentials

- IMAP credentials stored in `~/.config/siegfried/email_credentials.json` (chmod 600)
- API keys stored in `~/.config/siegfried/api_keys.json` (chmod 600)
- Gateway token read from OpenClaw config
- No credentials stored in the skill directory or config.yaml

## Statistics & Observability

All triage runs are logged to `stats/triage.log`:

```
2026-02-07T13:00:00+01:00 OK latency_ms=450 quiet=false
2026-02-07T13:00:30+01:00 DEFER reason="2 non-urgent emails" latency_ms=520 quiet=false
2026-02-07T13:01:00+01:00 ESCALATE reason="Meeting in 20min" latency_ms=480 quiet=false
2026-02-07T03:15:00+01:00 ESCALATE reason="disk 94% full" latency_ms=390 quiet=true
```

The assistant can parse this log to generate summaries: escalation rate, average latency, false positive tracking (with user feedback).

## Future Considerations

- **Adaptive intervals:** Increase frequency when signals are "warm" (e.g., expecting a reply)
- **Learning:** Track false positives/negatives to refine the triage prompt
- **Multi-account email:** Multiple IMAP accounts in one collector
- **Webhook signals:** Accept push notifications instead of polling
- **Triage model fine-tuning:** Use logged decisions as training data
