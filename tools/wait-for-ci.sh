#!/usr/bin/env bash
# CI-futás várakoztató, timeout-tal védett `gh` hívásokkal (ADR 0112 önjavító
# kör, E06-R25 H-NOSIGNAL, 2026-08-13).
#
#   tools/wait-for-ci.sh <run-id> [max_wait-mp] [hívásonkénti-timeout-mp]
#
# MIÉRT KELL: sem a `gh run watch <id>`, sem a kézzel írt `gh run list`
# poll-ciklus (docs/execution/pipeline-orchestrator-prompt.md,
# .claude/skills/sdd-round-driver/SKILL.md §5 korábbi ajánlása) NEM védett
# timeout-tal egyetlen `gh` hívást sem. Mérve (E06-R25, 2026-08-13T13:30Z
# körül, session-napló
# .pipeline/session-E06-R25-20260813T123506-fallback.log): 13 egymást követő
# `gh run list --workflow full-gate.yml ...` hívás ~25,5s alatt tért vissza
# ("succeeded in 25478ms" .. "25643ms" mintázat), a 14. SOHA -- a session a
# hívás BELSEJÉBEN fagyott le, új sort többé nem írt a naplóba. A pipeline 20
# perces log-mtime elakadás-őre (round-pipeline.sh ELAKADÁS-ŐR) csak
# KÍVÜLRŐL, a TELJES sessiont ölve tudta ezt észlelni -- jóval azután, hogy a
# ténylegesen várt CI-futás (Full Gate, databaseId 31704364552) már zölden
# lezárult (13:33:34Z). Két önjavító kör és több mint egy óra ment el emiatt
# egyetlen védtelen hálózati hívás miatt.
#
# Ez a szkript EGYETLEN `gh run view` hívást sem enged a hívásonkénti
# timeout-nál tovább futni: hang esetén azt a HÍVÁST öli meg a `timeout`, nem
# a teljes várakozást fagyasztja le -- és `WAIT_CI_MAX_GH_FAILURES` egymást
# követő hang/hiba után KÜLÖN, gyors kilépési kóddal jelzi, hogy maga a
# `gh`/hálózat akadt el, ez NEM ugyanaz, mint "a workflow még fut".
#
# Kilépési kód:
#   0 = a futás terminális, `conclusion=success` (a `status\tconclusion` sor stdout-on)
#   1 = a futás terminális, de NEM success (a `status\tconclusion` sor stdout-on)
#   2 = használati hiba (hiányzó run-id)
#   4 = letelt a `max_wait`, a futás MÉG NEM terminális (talán még fut)
#   6 = `WAIT_CI_MAX_GH_FAILURES` egymást követő `gh`-timeout/hiba -- a
#       hálózat/a `gh` maga akadt el, nem a workflow-t kell tovább várni
#
# A várakozás -- a wait-for-round.sh/wait-for-router.sh mintájához hasonlóan
# -- pollingol, de itt a lekérdezett ÁLLAPOT maga is egy (hang-veszélyes)
# hálózati hívás eredménye, nem egy helyi jelzésfájl tartalma.
set -uo pipefail

if [ $# -lt 1 ] || [ -z "$1" ]; then
  echo "használat: wait-for-ci.sh <run-id> [max_wait-mp] [hívásonkénti-timeout-mp]" >&2
  exit 2
fi
run_id=$1
max_wait=${2:-1800}
call_timeout=${3:-${WAIT_CI_CALL_TIMEOUT_SECONDS:-60}}
poll=${WAIT_POLL_SECONDS:-20}
max_gh_failures=${WAIT_CI_MAX_GH_FAILURES:-5}

started=$(date +%s)
consecutive_failures=0

while true; do
  output=$(timeout "${call_timeout}s" gh run view "$run_id" --json status,conclusion --jq '[.status,.conclusion] | @tsv' 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ]; then
    consecutive_failures=0
    IFS=$'\t' read -r status conclusion <<<"$output"
    if [ "$status" = "completed" ]; then
      printf '%s\n' "$output"
      [ "$conclusion" = "success" ] && exit 0
      exit 1
    fi
  else
    consecutive_failures=$(( consecutive_failures + 1 ))
    if [ "$rc" -eq 124 ]; then
      echo "wait-for-ci.sh: a 'gh run view $run_id' hívás ${call_timeout}s után timeout-olt (${consecutive_failures}/${max_gh_failures})" >&2
    else
      echo "wait-for-ci.sh: a 'gh run view $run_id' hívás hibázott (rc=$rc, ${consecutive_failures}/${max_gh_failures}): $output" >&2
    fi
    if [ "$consecutive_failures" -ge "$max_gh_failures" ]; then
      echo "wait-for-ci.sh: $max_gh_failures egymást követő 'gh' hiba/timeout -- a hálózat/gh akadt el, ez NEM azt jelenti, hogy a workflow még fut" >&2
      exit 6
    fi
  fi

  now=$(date +%s)
  if [ $(( now - started )) -ge "$max_wait" ]; then
    echo "wait-for-ci.sh: letelt a várakozás (${max_wait}s) -- a futás MÉG TARTHAT." >&2
    exit 4
  fi
  sleep "$poll"
done
