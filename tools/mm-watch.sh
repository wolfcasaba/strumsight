#!/usr/bin/env bash
# Korai riasztás a futó MiniMax-körre (AGENTS.md §15.3, ADR 0069).
#
#   tools/mm-watch.sh <munkapéldány> [logfájl]
#
# Az orchestrátor ezt MÁSODIK háttér-taskként indítja a mm-round.sh mellé.
# Akkor lép ki (= akkor értesül a hívó), amint BÁRMI figyelmet igényel:
#   - az implementer lezáró jelzést írt (done / stopped / blocked),
#   - a folyamat eltűnt,
#   - vagy a log MM_STALL_MINUTES perce nem nő (beragadás; alap: 5 perc).
#
# A mm-round.sh stream-json formátumban logol, ezért a log eseményenként nő —
# az 5 perces küszöb valódi elakadást jelent, nem pufferelést (user-szabály
# 2026-07-30: "nem kell nagy időtáv").
set -uo pipefail

workdir=${1:?használat: mm-watch.sh <munkapéldány> [logfájl]}
workdir=$(readlink -f "$workdir")
log_file=${2:-/tmp/mm-$(basename "$workdir").log}
stall_minutes=${MM_STALL_MINUTES:-5}
signal="$workdir/.codex-round-status"
pid_file="$workdir/.mm-round-pid"

# A log utolsó néhány lépése emberi nyelven — a stream-json eseményekből.
summarize_tail() {
  python3 - "$log_file" <<'PY' 2>/dev/null || tail -5 "$log_file"
import json, sys
steps = []
for line in open(sys.argv[1], errors="replace"):
    line = line.strip()
    if not line.startswith("{"):
        continue
    try:
        event = json.loads(line)
    except ValueError:
        continue
    for block in (event.get("message") or {}).get("content", []) or []:
        if not isinstance(block, dict):
            continue
        if block.get("type") == "tool_use":
            args = block.get("input") or {}
            detail = args.get("file_path") or args.get("command") or args.get("pattern") or ""
            steps.append(f"{block.get('name')}: {str(detail)[:110]}")
        elif block.get("type") == "text" and block.get("text", "").strip():
            steps.append("text: " + block["text"].strip().replace("\n", " ")[:110])
print("\n".join(steps[-8:]) or "(még nincs értelmezhető esemény a logban)")
PY
}

while true; do
  if [ -f "$signal" ] && grep -qE '^status=(done|stopped|blocked)$' "$signal"; then
    echo "--- minimax signalled ---"
    cat "$signal"
    exit 0
  fi

  if [ -f "$pid_file" ] && ! kill -0 "$(cat "$pid_file")" 2>/dev/null; then
    echo "--- minimax process is gone ---"
    [ -f "$signal" ] && cat "$signal" || echo "status=unknown (nincs jelzésfájl)"
    summarize_tail
    exit 0
  fi

  if [ -f "$log_file" ] && [ $(( $(date +%s) - $(stat -c %Y "$log_file") )) -ge $(( stall_minutes * 60 )) ]; then
    echo "--- minimax stalled: a log ${stall_minutes} perce nem nő ---"
    summarize_tail
    exit 0
  fi

  sleep 20
done
