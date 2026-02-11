#!/usr/bin/env bash
# Build a release archive with only the files needed for installation.
# Usage: bash scripts/build-release.sh [version]
# Output: turbo-heartbeat-<version>.tar.gz

set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-$(git describe --tags --always 2>/dev/null || echo "dev")}"
OUT="turbo-heartbeat-${VERSION}.tar.gz"

echo "Building release: $OUT"

tar czf "$OUT" \
  --transform="s,^,turbo-heartbeat/," \
  README.md \
  LICENSE \
  install.sh \
  config.example.yaml \
  scripts/detect-env.sh \
  scripts/triage.sh \
  scripts/escalate.sh \
  scripts/notify-critical.sh \
  scripts/health-check.sh \
  scripts/signals/system.sh \
  scripts/signals/email_imap.sh \
  scripts/signals/calendar.sh \
  templates/triage-prompt.md

echo "Done: $OUT ($(du -h "$OUT" | cut -f1))"
echo ""
echo "Excluded from release: docs/, tests/, stats/, .git/, config.yaml"
