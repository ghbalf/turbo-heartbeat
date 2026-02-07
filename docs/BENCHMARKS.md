# Turbo-Heartbeat Benchmarks

*Tested: 2026-02-07*
*Platform: ARM64 (aarch64), 20 cores, 122 GB RAM, Ollama 0.15.5*
*No GPU — CPU inference only*

## Triage Accuracy

### GLM-4.7-Flash (9B) — Local via Ollama

Test suite: 12 scenarios covering all signal types and decision categories.

| # | Scenario | Expected | Got | Pass |
|---|----------|----------|-----|------|
| 1 | All signals OK | OK | OK | ✅ |
| 2 | 1 unread email from unknown | DEFER | DEFER | ✅ |
| 3 | 3 unread, 1 from boss "Urgent review" | ESCALATE | ESCALATE | ✅ |
| 4 | Meeting in 25 minutes | ESCALATE | ESCALATE | ✅ |
| 5 | Meeting in 3 hours | DEFER | OK | ⚠️ |
| 6 | Disk 94% full | ESCALATE | ESCALATE | ✅ |
| 7 | Memory 96% used | ESCALATE | ESCALATE | ✅ |
| 8 | Newsletter + low disk warning | DEFER | DEFER | ✅ |
| 9 | Empty signals (all OK) | OK | OK | ✅ |
| 10 | Calendar event tomorrow | OK | OK | ✅ |
| 11 | 5 unread, all newsletters | DEFER | DEFER | ✅ |
| 12 | Security alert email + disk 90% | ESCALATE | ESCALATE | ✅ |

**Result: 11/12 (92%)**

The only miss: Scenario 5 ("Meeting in 3 hours") was classified as OK instead of DEFER. This is an acceptable edge case — the meeting is far enough away that the regular heartbeat (30 min) will catch it before it becomes urgent.

### Important: `think: false`

GLM-4.7-Flash must be called with `"think": false` in the API payload. Without this flag, the model spends all tokens on internal reasoning and returns an empty response. This is a known GLM behavior.

## Latency

### End-to-End Triage Cycle (Local, GLM-4.7-Flash)

| Phase | Time |
|-------|------|
| Signal collection (3 collectors) | ~200ms |
| Triage model inference | ~400-500ms |
| **Total** | **~600-700ms** |

### Breakdown by Collector

| Collector | Avg Time | Notes |
|-----------|----------|-------|
| system.sh | ~50ms | Pure local (df, free, ps) |
| email_imap.sh | ~100-150ms | IMAP SSL connection to strato.de |
| calendar.sh | ~50ms | gcalcli (local calendar cache) |

### Latency Distribution (50 runs)

```
P50:  580ms
P90:  720ms
P95:  810ms
P99:  1100ms
Max:  1350ms (IMAP connection slow)
```

## Cost Analysis

### Before Turbo-Heartbeat (Cloud Heartbeats Only)

| Setting | Value |
|---------|-------|
| Model | Claude Opus 4.6 |
| Heartbeat interval | ~30 min |
| Heartbeats/day | ~48 |
| Input tokens/heartbeat | ~2000-4000 (context + HEARTBEAT.md) |
| Output tokens/heartbeat | ~20-200 (HEARTBEAT_OK or action) |
| Estimated cost/heartbeat | $0.05-0.15 |
| **Estimated cost/day** | **$2.40-7.20** |
| **Estimated cost/month** | **$72-216** |

### After Turbo-Heartbeat (Profile A: Local)

| Setting | Value |
|---------|-------|
| Triage model | GLM-4.7-Flash (local) |
| Triage interval | 30 seconds |
| Triage checks/day | 2,880 |
| Triage cost | **$0.00** |
| Escalations/day (est.) | 5-15 |
| Main model cost/escalation | $0.05-0.15 |
| Regular heartbeat (safety net) | 48/day |
| **Estimated cost/day** | **$0.25-2.25** + safety net |
| **Estimated cost/month** | **$7.50-67.50** |

### Savings

| Metric | Before | After (Profile A) | Savings |
|--------|--------|-------------------|---------|
| Reaction time | 30 min | 30-60 sec | **60× faster** |
| Daily cost | $2.40-7.20 | $0.25-2.25 | **70-90% less** |
| Monthly cost | $72-216 | $7.50-67.50 | **$65-150/month** |

> Note: Actual savings depend on escalation frequency. More escalations = less savings, but also more value delivered.

### Profile B (Remote, Free-Tier) Cost

| Setting | Value |
|---------|-------|
| Triage model | Groq llama-3.3-70b (free) |
| Triage interval | 5 minutes |
| Triage checks/day | 288 |
| Triage cost | **$0.00** (free tier) |
| Escalations/day (est.) | 5-15 |
| **Estimated cost/day** | **$0.25-2.25** |

## Resource Usage

### CPU Impact (Local, GLM-4.7-Flash, 30s interval)

| Metric | Value |
|--------|-------|
| CPU during triage | ~40-60% (burst, <1s) |
| CPU idle between triages | ~0% |
| Avg CPU over time | ~2-3% |
| Impact on other processes | Negligible |

### Memory Impact

| Component | RAM |
|-----------|-----|
| GLM-4.7-Flash (loaded) | ~8 GB |
| Ollama overhead | ~200 MB |
| triage.sh + collectors | ~10 MB |
| **Total** | **~8.2 GB** |

Note: Ollama keeps the model loaded between calls (default 5 min keepalive), so there's no repeated load time. With a 30s interval, the model stays hot.

### Disk I/O

| Activity | Impact |
|----------|--------|
| triage.log writes | ~100 bytes/entry, <1 KB/min |
| Signal collection | Negligible reads |
| Model inference | Memory-mapped, minimal I/O |

## Comparison with Alternatives

| Approach | Reaction Time | Cost/Day | Complexity |
|----------|--------------|----------|------------|
| Cloud heartbeat every 30 min | 30 min | $2.40-7.20 | Low |
| Cloud heartbeat every 5 min | 5 min | $14.40-43.20 | Low |
| Cloud heartbeat every 1 min | 1 min | $72-216 | Low |
| **Turbo-Heartbeat (Local)** | **30-60s** | **$0.25-2.25** | **Medium** |
| Turbo-Heartbeat (Remote) | 5-6 min | $0.25-2.25 | Medium |

Turbo-Heartbeat achieves the fastest reaction time at the lowest cost by using a cheap triage model for frequent checks and reserving the expensive model for actual work.

---

*Benchmarks will be updated as more models and hardware configurations are tested.*
