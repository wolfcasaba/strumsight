#!/usr/bin/env bash
# Kör-várakoztató az ORCHESTRÁTOR oldalán (AGENTS.md §15.2, docs/LESSONS.md L12).
#
#   tools/wait-for-round.sh <munkapéldány> [időkorlát-mp]
#
# Blokkol, amíg az implementer kör-jelzése terminális állapotba nem ér
# (`done` | `stopped` | `stalled` | `timeout` | `unknown`), majd kiírja a teljes
# jelzésfájlt és a megfelelő kilépési kóddal tér vissza:
#
#   0 = done
#   3 = stopped   (az implementer kérdez / scope-ütközés — döntést vár tőled)
#   4 = stalled | timeout | unknown  (a futás nem ért végig)
#   5 = a várakozás időkorlátja járt le (a kör MÉG FUTHAT)
#
# MIÉRT SCRIPT, és miért nem egy `until pgrep …` egysoros:
# az E02-R08-ban az orchestrátor egy `until ! pgrep -f "mm-r08-resume.sh"`
# ciklussal várt. A `pgrep -f` mintája illeszkedett a VÁRAKOZÓ CIKLUS SAJÁT
# parancssorára is, tehát a feltétel sosem vált igazzá: az implementer 01:05-kor
# `stopped` jelzéssel megállt és döntést kért, az orchestrátor viszont további
# HAT ÓRÁN át azt hitte, hogy a kör fut. A hiba osztálya általános, ezért a
# helyes várakozás futtatható artefaktum, nem promptban újraírt egysoros.
#
# A várakozás a JELZÉSFÁJLRA megy, nem processz-életre — ez a szerződés (§15.2),
# és processz-életnél az is kiderül belőle, hogy a kör MIÉRT ért véget.
set -uo pipefail

workdir=${1:?használat: wait-for-round.sh <munkapéldány> [időkorlát-mp]}
max_wait=${2:-7200}
poll=${WAIT_POLL_SECONDS:-20}

workdir=$(readlink -f "$workdir")
signal="$workdir/.codex-round-status"

if [ ! -d "$workdir" ]; then
  echo "wait-for-round.sh: nincs ilyen munkapéldány: $workdir" >&2
  exit 2
fi

started=$(date +%s)
# A kiinduló időbélyeg: egy KORÁBBI kör terminális jelzése ne zárja le azonnal
# a várakozást (E02-R08 resume — a `stalled` jelzés bent maradt a fájlban).
#
# A baseline egy MARKER-fájlban él, nem csak ebben a folyamatban (MÉRT rés,
# E07-R19 H-NOSIGNAL önjavítás, 2026-08-18). Egyes orchestrátor-harnessek
# (Terra/Codex `exec_command`+`wait`) csendes parancsnál önmaguktól
# „yield"-elnek, ezért a hívó a dokumentált „exit 5 → hívd meg újra"
# szerződés szerint sok, egyenként FRISS folyamatként indítja ezt a scriptet,
# nem egyetlen hosszan futó hívásként. Egy tisztán memóriabeli baseline ekkor
# minden friss folyamat SAJÁT indulási pillanatában újraszámolódna a
# jelzésfájl AKKORI tartalmából — egy, a tényleges befejezés UTÁN induló
# friss hívás a friss `done`-t tekintené baseline-nak, és sosem jelentené
# késznek, amíg a `max_wait` le nem jár. Mérve: `.codex-round-status`
# `status=done`/`signalled_at=2026-08-18T12:30:06Z` már készen és pusholva
# állt, az orchestrátor mégis 12:37:08-ig, 7 percen át üres kimenetet kapott
# minden friss hívástól (session rollout `01a014b9…`, ismételt
# `tools/wait-for-round.sh … 540` hívások, mindegyik ~15–28 mp után "Script
# completed", üres output), majd jelzés nélkül elfogyott a turnja —
# H-NOSIGNAL. A marker a baseline-t az ELSŐ hívástól a terminális
# kézbesítésig megőrzi, hogy a köztes friss újraindítások UGYANAZT lássák,
# ne a saját indulásuk pillanatát.
marker="$workdir/.wait-for-round-baseline"
if [ -f "$marker" ]; then
  baseline=$(cat "$marker" 2>/dev/null || true)
else
  baseline=""
  [ -f "$signal" ] && baseline=$(grep -m1 '^signalled_at=' "$signal" 2>/dev/null || true)
  printf '%s' "$baseline" > "$marker"
fi

while true; do
  if [ -f "$signal" ]; then
    stamp=$(grep -m1 '^signalled_at=' "$signal" 2>/dev/null || true)
    status=$(grep -m1 '^status=' "$signal" 2>/dev/null | cut -d= -f2- || true)
    if [ "$stamp" != "$baseline" ] || [ -z "$baseline" ]; then
      case "$status" in
        done)
          rm -f "$marker"
          cat "$signal"
          exit 0
          ;;
        stopped)
          rm -f "$marker"
          cat "$signal"
          echo
          echo "→ Az implementer DÖNTÉST VÁR. Olvasd el a summary mezőt, dönts," >&2
          echo "  és dokumentált brief-revízióval (§0.0) folytasd — ne lista-tágítással." >&2
          exit 3
          ;;
        stalled|timeout|unknown)
          rm -f "$marker"
          cat "$signal"
          echo
          echo "→ A futás nem ért végig ($status). Resume UGYANAZZAL a session-iddel," >&2
          echo "  és a teljes gate-mátrix újrafuttatásával (docs/LESSONS.md L12)." >&2
          exit 4
          ;;
      esac
    fi
  fi

  now=$(date +%s)
  if [ $(( now - started )) -ge "$max_wait" ]; then
    echo "wait-for-round.sh: letelt a várakozás ($max_wait s) — a kör MÉG FUTHAT." >&2
    [ -f "$signal" ] && cat "$signal"
    exit 5
  fi
  sleep "$poll"
done
