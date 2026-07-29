#!/usr/bin/env bash
# Codex-oldali kör-jelzés (AGENTS.md §15.2). A Codex ezzel szól az őt indító
# ágensnek — a jelzés a kör MINDEN kimenetelére kötelező, nem csak a sikerre.
#
#   tools/codex-signal.sh progress      "route katalógus kész, jönnek a tesztek"
#   tools/codex-signal.sh code-complete "kód kész + pusholva, format/analyze zöld"
#   tools/codex-signal.sh done          "a §10 handoff is kitöltve, végeztem"
#   tools/codex-signal.sh stopped       "brief §5.8 ütközik az onboarding first-win úttal"
#   tools/codex-signal.sh blocked       "flutter analyze 3 javítás után is piros"
#
# A `code-complete` a CI ÁTADÁSA (AGENTS.md §15.3): a figyelő ekkor azonnal
# dispatch-eli a teljes CI-t, és az a jelentésírás + review alatt fut. Ezért
# csak akkor jelezd, ha a commit már fel van tolva — különben a CI-bizonyíték
# régi commitra futna.
#
# FONTOS: problémánál a jelzés az ELSŐ lépés, nem az utolsó. Előbb jelezz,
# utána írd meg a részletes jelentést — így az orchestrátor másodpercekben
# értesül, nem a futás végén (user-szabály 2026-07-29: "ne várjunk fél napot").
#
# A `progress` nem zárja le a kört; a `done` / `stopped` / `blocked` igen.
set -euo pipefail

status=${1:-}
shift || true
summary=${*:-}

case "$status" in
  progress | code-complete | done | stopped | blocked) ;;
  *)
    echo "usage: codex-signal.sh <progress|code-complete|done|stopped|blocked> \"<egy soros összegzés>\"" >&2
    exit 2
    ;;
esac

if [ -z "$summary" ]; then
  echo "codex-signal.sh: az összegzés kötelező — az orchestrátor ebből tudja, mi történt" >&2
  exit 2
fi

root=$(git rev-parse --show-toplevel)
signal="$root/.codex-round-status"

# Egy soros értékek: a summary újsorai szóközzé válnak, hogy a fájl
# grep-elhető KEY=VALUE maradjon.
{
  echo "status=$status"
  echo "summary=$(printf '%s' "$summary" | tr '\n' ' ')"
  echo "branch=$(git branch --show-current)"
  echo "head=$(git rev-parse --short HEAD)"
  echo "dirty_files=$(git status --porcelain | wc -l | tr -d ' ')"
  echo "signalled_at=$(date -Iseconds)"
} > "$signal"

echo "signalled: $status — $summary"
