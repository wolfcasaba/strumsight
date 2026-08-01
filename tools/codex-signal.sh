#!/usr/bin/env bash
# Implementer/router signal consumed by the round orchestrator.
#
# Legacy:
#   tools/codex-signal.sh progress|done|stopped|blocked "summary"
# Router:
#   tools/codex-signal.sh READY_FOR_REVIEW|STOPPED|DEFERRED|BLOCKED|INTERNAL_ERROR "summary"
#
# READY_FOR_REVIEW is deliberately progress, never final done. Only the
# independent review + CI + merge path may emit done.
set -euo pipefail
umask 077

input_status=${1:-}
shift || true
summary=${*:-}
router_status=""

case "$input_status" in
  progress | done | stopped | blocked)
    status=$input_status
    ;;
  READY_FOR_REVIEW)
    status=progress
    router_status=$input_status
    ;;
  STOPPED)
    status=stopped
    router_status=$input_status
    ;;
  DEFERRED | BLOCKED | INTERNAL_ERROR)
    status=blocked
    router_status=$input_status
    ;;
  *)
    echo "usage: codex-signal.sh <progress|done|stopped|blocked|READY_FOR_REVIEW|STOPPED|DEFERRED|BLOCKED|INTERNAL_ERROR> \"<egy soros összegzés>\"" >&2
    exit 2
    ;;
esac

if [ -z "$summary" ]; then
  echo "codex-signal.sh: az összegzés kötelező" >&2
  exit 2
fi

# The summary crosses a trust boundary. Redact common credentials, collapse
# newlines and cap it so neither a prompt nor a provider response becomes state.
safe_summary=$(printf '%s' "$summary" | python3 -c '
import re, sys
value = sys.stdin.read()
value = re.sub(r"(?i)(Authorization\s*:\s*Bearer\s+)\S+", r"\1[REDACTED]", value)
value = re.sub(r"(?i)\b(MINIMAX_API_KEY|OPENAI_API_KEY|CODEX_API_KEY|API_KEY|TOKEN)\s*=\s*\S+", r"\1=[REDACTED]", value)
value = re.sub(r"\bsk-[A-Za-z0-9_-]{20,}\b", "[REDACTED]", value)
print(" ".join(value.split())[:500])
')
[ -n "$safe_summary" ] || safe_summary="[REDACTED]"

root=$(git rev-parse --show-toplevel)
signal="$root/.codex-round-status"
temporary="$signal.tmp.$$"
{
  echo "status=$status"
  [ -z "$router_status" ] || echo "router_status=$router_status"
  echo "summary=$safe_summary"
  echo "branch=$(git branch --show-current)"
  echo "head=$(git rev-parse --short HEAD)"
  echo "dirty_files=$(git status --porcelain | wc -l | tr -d ' ')"
  echo "signalled_at=$(date -Iseconds)"
} > "$temporary"
chmod 600 "$temporary"
mv -f "$temporary" "$signal"

if [ -n "${PIPELINE_ROUTER_STATUS_FILE:-}" ]; then
  mirror=$PIPELINE_ROUTER_STATUS_FILE
  mkdir -p "$(dirname "$mirror")"
  mirror_temporary="$mirror.tmp.$$"
  cp "$signal" "$mirror_temporary"
  chmod 600 "$mirror_temporary"
  mv -f "$mirror_temporary" "$mirror"
fi

echo "signalled: $status — $safe_summary"
