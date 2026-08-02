#!/usr/bin/env bash
# Router-várakoztató az ORCHESTRÁTOR oldalán (ADR 0112 önjavító kör, 2026-08-02
# — E03-R05 H6, docs/LESSONS.md L42 pontos ismétlődése az `engine=auto` úton).
#
#   tools/wait-for-router.sh <munkapéldány> [időkorlát-mp]
#
# MIÉRT KÜLÖN SZKRIPT, és miért nem elég az örökölt `wait-for-round.sh`: az
# az implementer-motorok (`minimax`/`codex`) jelzés-szótárát ismeri
# (`case`-ága: `done|stopped|stalled|timeout|unknown`). A router
# (`ai-router-round.sh` → `codex-signal.sh`) viszont MÁS szótárat ír ugyanabba
# a `.codex-round-status` fájlba: `status=progress|stopped|blocked` +
# egy `router_status=READY_FOR_REVIEW|STOPPED|DEFERRED|BLOCKED|INTERNAL_ERROR`
# mező (lásd `tools/codex-signal.sh` router-ágát). A `wait-for-round.sh`
# `case`-ága a `progress`-ot és a `blocked`-ot NEM ismeri fel — egyik esetben
# sem lép ki egyik ágon sem, hanem visszaesik a ciklus tetejére és a
# `max_wait` leteltéig pörög (mérve: `tools/tests/test_pipeline_integration.py`
# `test_wait_for_round_does_not_recognize_router_terminal_signals`).
#
# A router-oldalon viszont `router_status=` mező jelenléte MINDIG terminális:
# az `ai-router-round.sh` a `codex-signal.sh`-t PONTOSAN EGYSZER hívja, a
# blokkoló `model-router.py` hívás UTÁN (tools/ai-router-round.sh:~95). Ez a
# szkript erre a mezőre vár, nem a `wait-for-round.sh` státusz-halmazára.
#
# Ez teszi lehetővé, hogy az orchestrátor a router-hívást `setsid ... &`-fal a
# Bash-eszköz saját, mért kemény plafonja (600s) MÖGÜL kiszabadítsa — az a
# plafon rövidebb, mint egy `model_timeout_seconds=7200`-as MiniMax-hívás
# (.ai/router.toml), ezért egy szinkron hívás elkerülhetetlenül SIGTERM-mel
# hal meg, ha a modellhívás az orchestrátor Bash-hívásánál tovább tart —
# pontosan ez okozta az E03-R05 H6 haltot (két egymást követő szinkron
# `ai-router-round.sh run` hívás, mindkettő jelzés nélkül, `M3_CALL_1/RUNNING`
# fázisban halt meg).
#
# Kilépési kód:
#   0 = terminális router-jelzés érkezett (`router_status=` mezővel) — a
#       teljes jelzésfájl stdout-ra megy, az orchestrátor a
#       docs/execution/pipeline-orchestrator-prompt.md §1.1 táblázata szerint
#       dönt a `router_status` értékéből.
#   5 = letelt az időkorlát, a router MÉG FUTHAT — hívd meg újra UGYANAZZAL a
#       munkapéldánnyal (ne indítsd újra a `setsid`-es dispatchot).
#
# A várakozás — a `wait-for-round.sh`-hoz hasonlóan — a JELZÉSFÁJLRA megy, nem
# processz-életre.
set -uo pipefail

workdir=${1:?használat: wait-for-router.sh <munkapéldány> [időkorlát-mp]}
max_wait=${2:-540}
poll=${WAIT_POLL_SECONDS:-10}

workdir=$(readlink -f "$workdir")
signal="$workdir/.codex-round-status"

if [ ! -d "$workdir" ]; then
  echo "wait-for-router.sh: nincs ilyen munkapéldány: $workdir" >&2
  exit 2
fi

started=$(date +%s)
# A kiinduló időbélyeg: egy KORÁBBI kör terminális jelzése ne zárja le azonnal
# a várakozást (ugyanaz a védelem, mint wait-for-round.sh-nál).
baseline=""
[ -f "$signal" ] && baseline=$(grep -m1 '^signalled_at=' "$signal" 2>/dev/null || true)

while true; do
  if [ -f "$signal" ]; then
    stamp=$(grep -m1 '^signalled_at=' "$signal" 2>/dev/null || true)
    if { [ "$stamp" != "$baseline" ] || [ -z "$baseline" ]; } && grep -q '^router_status=' "$signal" 2>/dev/null; then
      cat "$signal"
      exit 0
    fi
  fi

  now=$(date +%s)
  if [ $(( now - started )) -ge "$max_wait" ]; then
    echo "wait-for-router.sh: letelt a várakozás ($max_wait s) — a router MÉG FUTHAT." >&2
    [ -f "$signal" ] && cat "$signal"
    exit 5
  fi
  sleep "$poll"
done
