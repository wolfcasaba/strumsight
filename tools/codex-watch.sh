#!/usr/bin/env bash
# Korai riasztás a futó Codex-körre (AGENTS.md §15.3).
#
#   tools/codex-watch.sh <munkapéldány> [logfájl]
#
# Az orchestrátor ezt MÁSODIK háttér-taskként indítja a codex-round.sh mellé.
# Akkor lép ki (= akkor értesül a hívó), amint BÁRMI figyelmet igényel:
#   - a Codex lezáró jelzést írt (done / stopped / blocked),
#   - a folyamat eltűnt,
#   - vagy a log CODEX_STALL_MINUTES perce nem nő (beragadás).
#
# Így egy megállási pontról másodpercekben értesülünk, nem a futás végén —
# a codex-round.sh kilépése ehhez képest a biztonsági háló.
set -uo pipefail

workdir=${1:?használat: codex-watch.sh <munkapéldány> [logfájl]}
log_file=${2:-/tmp/codex-$(basename "$workdir").log}
stall_minutes=${CODEX_STALL_MINUTES:-12}
signal="$workdir/.codex-round-status"

while true; do
  if [ -f "$signal" ] && grep -qE '^status=(done|stopped|blocked)$' "$signal"; then
    echo "--- codex signalled ---"
    cat "$signal"
    exit 0
  fi

  if ! pgrep -f "codex exec -C $workdir" > /dev/null; then
    echo "--- codex process is gone ---"
    [ -f "$signal" ] && cat "$signal" || echo "status=unknown (nincs jelzésfájl)"
    exit 0
  fi

  if [ -f "$log_file" ] && [ $(( $(date +%s) - $(stat -c %Y "$log_file") )) -ge $(( stall_minutes * 60 )) ]; then
    echo "--- codex stalled: a log ${stall_minutes} perce nem nő ---"
    tail -20 "$log_file"
    exit 0
  fi

  sleep 20
done
