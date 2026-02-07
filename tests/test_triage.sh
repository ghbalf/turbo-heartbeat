#!/bin/bash
# Turbo-Heartbeat: Triage Model Test Suite
# Tests various signal combinations against the triage model

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROMPT=$(cat "$SKILL_DIR/templates/triage-prompt.md")
MODEL="${1:-glm-4.7-flash}"
PASS=0
FAIL=0
TOTAL=0

echo "============================================================"
echo "🐉 Turbo-Heartbeat Triage Test Suite"
echo "Model: $MODEL"
echo "============================================================"
echo ""

run_test() {
    local test_name="$1"
    local signals="$2"
    local expected="$3"  # OK, ESCALATE, DEFER
    
    TOTAL=$((TOTAL + 1))
    
    echo -n "Test $TOTAL: $test_name ... "
    
    START_MS=$(date +%s%N)
    RESPONSE=$(echo "$signals" | ollama run "$MODEL" "$PROMPT" 2>/dev/null | head -1 | tr -d '\r')
    END_MS=$(date +%s%N)
    LATENCY=$(( (END_MS - START_MS) / 1000000 ))
    
    # Check if response starts with expected
    ACTUAL=$(echo "$RESPONSE" | cut -d: -f1 | tr -d ' ')
    
    if [ "$ACTUAL" = "$expected" ]; then
        echo "✅ PASS (${LATENCY}ms) → $RESPONSE"
        PASS=$((PASS + 1))
    else
        echo "❌ FAIL (${LATENCY}ms)"
        echo "   Expected: $expected"
        echo "   Got:      $RESPONSE"
        FAIL=$((FAIL + 1))
    fi
}

# === TEST CASES ===

echo "--- Scenario 1: All Clear ---"
run_test "Everything OK" \
    "SYSTEM: OK
EMAIL: OK
CALENDAR: OK" \
    "OK"

echo ""
echo "--- Scenario 2: Urgent Email ---"
run_test "Unread emails" \
    "SYSTEM: OK
EMAIL: 5 unread (1 from bank@security.com, subject: Unusual login detected)
CALENDAR: OK" \
    "ESCALATE"

echo ""
echo "--- Scenario 3: Calendar Imminent ---"
run_test "Meeting in 15 minutes" \
    "SYSTEM: OK
EMAIL: OK
CALENDAR: Meeting 'Doctor appointment' in 15 minutes" \
    "ESCALATE"

echo ""
echo "--- Scenario 4: Calendar Far Away ---"
run_test "Meeting in 3 hours" \
    "SYSTEM: OK
EMAIL: OK
CALENDAR: Meeting 'Team standup' in 3 hours" \
    "DEFER"

echo ""
echo "--- Scenario 5: Disk Critical ---"
run_test "Disk 95% full" \
    "SYSTEM: ALERT — disk 95% full
EMAIL: OK
CALENDAR: OK" \
    "ESCALATE"

echo ""
echo "--- Scenario 6: Memory Critical ---"
run_test "Memory 97%" \
    "SYSTEM: ALERT — memory 97%
EMAIL: OK
CALENDAR: OK" \
    "ESCALATE"

echo ""
echo "--- Scenario 7: Ollama Down ---"
run_test "Ollama not running" \
    "SYSTEM: ALERT — ollama not running
EMAIL: OK
CALENDAR: OK" \
    "ESCALATE"

echo ""
echo "--- Scenario 8: Low Priority Email ---"
run_test "Newsletter emails" \
    "SYSTEM: OK
EMAIL: 2 unread (newsletter@shop.com, promo@deals.com)
CALENDAR: OK" \
    "DEFER"

echo ""
echo "--- Scenario 9: Multiple Alerts ---"
run_test "Disk + urgent email" \
    "SYSTEM: ALERT — disk 92% full
EMAIL: 3 unread (1 from boss@company.com, subject: URGENT: Server issue)
CALENDAR: Meeting 'Emergency standup' in 10 minutes" \
    "ESCALATE"

echo ""
echo "--- Scenario 10: Only System OK ---"
run_test "System only, no other signals" \
    "SYSTEM: OK" \
    "OK"

echo ""
echo "--- Scenario 11: Gateway Down ---"
run_test "OpenClaw gateway down" \
    "SYSTEM: ALERT — openclaw-gateway down
EMAIL: OK
CALENDAR: OK" \
    "ESCALATE"

echo ""
echo "--- Scenario 12: Mixed Non-Urgent ---"
run_test "Non-urgent email + distant calendar" \
    "SYSTEM: OK
EMAIL: 1 unread (friend@gmail.com, subject: Check out this cool video)
CALENDAR: Dentist appointment in 5 hours" \
    "DEFER"

# === RESULTS ===
echo ""
echo "============================================================"
echo "📊 Results: $PASS/$TOTAL passed, $FAIL failed"
echo "Model: $MODEL"
echo "============================================================"

if [ "$FAIL" -eq 0 ]; then
    echo "🎉 ALL TESTS PASSED!"
else
    echo "⚠️  $FAIL test(s) failed — model may need different prompt or fine-tuning"
fi
