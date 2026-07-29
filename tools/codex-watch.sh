#!/usr/bin/env bash
# Korai riasztás + CI-átvétel a futó Codex-körre (AGENTS.md §15.3).
#
#   tools/codex-watch.sh <munkapéldány> [logfájl]
#
# Az orchestrátor ezt MÁSODIK háttér-taskként indítja a codex-round.sh mellé.
# Akkor lép ki (= akkor értesül a hívó), amint BÁRMI figyelmet igényel:
#   - a Codex jelzést írt (code-complete / done / stopped / blocked),
#   - a folyamat eltűnt,
#   - vagy a log CODEX_STALL_MINUTES perce nem nő (beragadás).
#
# **CI-ÁTVÉTEL** (user-szabály 2026-07-29): `code-complete` jelzésnél — vagyis
# amint a kód megvan, formázva, analyze-zal és feltolva — ez a script AZONNAL
# dispatch-eli a CI-t, még mielőtt a Codex a jelentését megírná. Így a CI a
# jelentés- és review-idő alatt fut, és a teszteket senki nem futtatja kétszer:
# lokálisan csak a kör SAJÁT új tesztjei mennek, a teljes regresszió (teljes
# suite + property gate + APK) egyszer, a CI-ban.
#
# A dispatch Claude-oldali marad (ADR 0055: a Codex nem hív `gh`-t) — a Codex
# csak jelez, a döntést ez a script hozza, és csak akkor, ha a branch tényleg
# fel van tolva (különben régi commitra futna a bizonyíték).
#
# Kikapcsolás: CODEX_AUTO_CI=0
set -uo pipefail

workdir=${1:?használat: codex-watch.sh <munkapéldány> [logfájl]}
log_file=${2:-/tmp/codex-$(basename "$workdir").log}
stall_minutes=${CODEX_STALL_MINUTES:-12}
auto_ci=${CODEX_AUTO_CI:-1}
signal="$workdir/.codex-round-status"

signal_value() { grep -m1 "^$1=" "$signal" 2>/dev/null | cut -d= -f2-; }

# A `pgrep -f "codex exec …"` a Codexet INDÍTÓ shellre is illeszkedik (a
# parancssora tartalmazza a mintát), ezért önmagában hamis „még fut"-ot ad —
# 2026-07-29-én pont ezt mérte be a figyelő. Csak a nem-shell processz számít.
codex_alive() {
  local pid comm
  for pid in $(pgrep -f "codex exec -C $workdir" 2>/dev/null); do
    [ "$pid" = "$$" ] && continue
    comm=$(ps -o comm= -p "$pid" 2>/dev/null)
    case "$comm" in
      bash | sh | dash | zsh | pgrep | ps | "") continue ;;
      *) return 0 ;;
    esac
  done
  return 1
}

dispatch_ci() {
  local branch head remote_head
  branch=$(git -C "$workdir" branch --show-current)
  head=$(git -C "$workdir" rev-parse HEAD)

  git -C "$workdir" fetch -q origin "$branch" 2>/dev/null
  remote_head=$(git -C "$workdir" rev-parse "origin/$branch" 2>/dev/null)

  if [ "$head" != "$remote_head" ]; then
    echo "CI NEM indult: a branch nincs feltolva (local ${head:0:7} != origin ${remote_head:0:7})."
    echo "A Codexnek push-olnia kell, mielőtt code-complete-et jelez."
    return 1
  fi

  if gh workflow run build-apk.yml --ref "$branch" 2>&1; then
    echo "CI dispatchelve: $branch @ ${head:0:7}"
  else
    echo "CI dispatch SIKERTELEN — indítsd kézzel: gh workflow run build-apk.yml --ref $branch"
  fi
}

while true; do
  if [ -f "$signal" ] && grep -qE '^status=(code-complete|done|stopped|blocked)$' "$signal"; then
    status=$(signal_value status)
    echo "--- codex signalled: $status ---"
    cat "$signal"
    if [ "$auto_ci" = "1" ] && { [ "$status" = "code-complete" ] || [ "$status" = "done" ]; }; then
      echo
      dispatch_ci
    fi
    exit 0
  fi

  if ! codex_alive; then
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
