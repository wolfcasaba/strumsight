#!/usr/bin/env bash
# Deterministic adapter between the Claude round orchestrator and model-router.py.
#
#   tools/ai-router-round.sh run    WORKTREE BRIEF RESULT_JSON
#   tools/ai-router-round.sh resume WORKTREE BRIEF RESULT_JSON [REVIEW_FINDINGS]
set -euo pipefail
umask 077

usage() {
  echo "usage: ai-router-round.sh <run|resume> <worktree> <brief> <result-json> [review-findings]" >&2
  exit 2
}

[ "$#" -ge 4 ] && [ "$#" -le 5 ] || usage
mode=$1
worktree_arg=$2
brief_arg=$3
result_arg=$4
findings_arg=${5:-}
case "$mode" in
  run) [ -z "$findings_arg" ] || usage ;;
  resume) ;;
  *) usage ;;
esac

worktree=$(realpath -e "$worktree_arg")
[ -d "$worktree/.git" ] || [ -f "$worktree/.git" ] || {
  echo "ai-router-round.sh: worktree is not a Git checkout" >&2
  exit 50
}

case "$brief_arg" in
  /*) brief_path=$(realpath -e "$brief_arg") ;;
  *) brief_path=$(realpath -e "$worktree/$brief_arg") ;;
esac
case "$result_arg" in
  /*) result_path=$(realpath -m "$result_arg") ;;
  *) result_path=$(realpath -m "$worktree/$result_arg") ;;
esac
case "$brief_path" in
  "$worktree"/*) ;;
  *) echo "ai-router-round.sh: brief must be inside the worktree" >&2; exit 50 ;;
esac
case "$result_path" in
  "$worktree"/.ai/runs/*) ;;
  *) echo "ai-router-round.sh: result must be under .ai/runs" >&2; exit 50 ;;
esac

router="$worktree/tools/model-router.py"
signal="$worktree/tools/codex-signal.sh"
[ -x "$router" ] || { echo "ai-router-round.sh: model router is unavailable" >&2; exit 50; }
[ -x "$signal" ] || { echo "ai-router-round.sh: signal helper is unavailable" >&2; exit 50; }
mkdir -p "$(dirname "$result_path")"
stdout_log="${result_path%.json}.stdout.log"
stderr_log="${result_path%.json}.stderr.log"

# The driver passes its router-status mirror to this isolated worktree. Keep
# an H4 handoff beside that mirror instead of in the worktree's own pipeline.
if [ -z "${PIPELINE_STATE_DIR:-}" ] && [ -n "${PIPELINE_ROUTER_STATUS_FILE:-}" ]; then
  export PIPELINE_STATE_DIR="$(dirname "$PIPELINE_ROUTER_STATUS_FILE")"
fi

command=(python3 "$router" "$mode" --task "$brief_path" --worktree "$worktree" --result-json "$result_path")
if [ "$mode" = "resume" ] && [ -n "$findings_arg" ]; then
  case "$findings_arg" in
    /*) findings_path=$(realpath -e "$findings_arg") ;;
    *) findings_path=$(realpath -e "$worktree/$findings_arg") ;;
  esac
  case "$findings_path" in
    "$worktree"/*) ;;
    *) echo "ai-router-round.sh: review findings must be inside the worktree" >&2; exit 50 ;;
  esac
  command+=(--review-findings "$findings_path")
fi

set +e
"${command[@]}" >"$stdout_log" 2>"$stderr_log"
router_exit=$?
set -e

signal_internal_error() {
  "$signal" INTERNAL_ERROR "$1"
  exit 50
}

[ -f "$result_path" ] || signal_internal_error "router result file is missing (exit $router_exit)"
mapfile -t fields < <(
  python3 -c '
import json, sys
from pathlib import Path
try:
    value = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    status = value.get("status")
    reason = value.get("reason", "")
    if not isinstance(status, str) or not isinstance(reason, str):
        raise ValueError("invalid types")
    print(status)
    print(" ".join(reason.split())[:500])
except Exception:
    raise SystemExit(2)
' "$result_path"
)
[ "${#fields[@]}" -eq 2 ] || signal_internal_error "router result is invalid"
router_status=${fields[0]}
reason=${fields[1]}

case "$router_status" in
  READY_FOR_REVIEW) expected_exit=0 ;;
  STOPPED) expected_exit=20 ;;
  DEFERRED) expected_exit=30 ;;
  BLOCKED) expected_exit=40 ;;
  INTERNAL_ERROR) expected_exit=50 ;;
  *) signal_internal_error "router returned an unknown status" ;;
esac
[ "$router_exit" -eq "$expected_exit" ] || signal_internal_error "router status and exit code disagree"

"$signal" "$router_status" "${reason:-router returned $router_status}"
exit "$expected_exit"
