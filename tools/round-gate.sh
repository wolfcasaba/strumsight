#!/usr/bin/env bash
# Kör-gate futtató (ADR 0052 zöld kapu, AGENTS.md §12).
#
#   tools/round-gate.sh <teszt-útvonal> [további teszt-útvonal ...]
#
# Példa:
#   tools/round-gate.sh test/features/practice/ test/property/practice_session_property_test.dart
#
# MIÉRT SCRIPT, és miért nem a promptban felsorolt parancsok:
# az E02-R07-ben az implementer motor HÁROMSZOR futtatta a gate-et
# `| tail -N`-nel, pedig a brief és a javító prompt is szó szerint tiltotta
# (docs/LESSONS.md L09 környéke, docs/reviews/e02-r07-review.md). A csővezeték
# elrejti a kilépési kódot és a hibalistát, így a „minden gate zöld" jelentés
# bizonyíthatatlan. A mérce ezért futtatható artefaktum, nem prompt-szöveg.
#
# A lépések KÜLÖN processzként futnak, egymás után — soha nem `analyze && test`
# egyetlen parancsban (ezen a boxon OOM-ol, docs/LESSONS.md L05). A kimenet
# csonkítatlanul megy a terminálra; az első piros lépésnél megállunk.
#
# Kilépési kód: 0 = minden lépés zöld, egyébként az első bukott lépés kódja.
set -uo pipefail

flutter_bin=${FLUTTER_BIN:-$HOME/flutter/bin/flutter}
dart_bin=${DART_BIN:-$HOME/flutter/bin/dart}

if [ ! -x "$flutter_bin" ] || [ ! -x "$dart_bin" ]; then
  echo "round-gate.sh: nincs futtatható flutter/dart ($flutter_bin, $dart_bin)" >&2
  echo "  állítsd be: FLUTTER_BIN=... DART_BIN=... tools/round-gate.sh ..." >&2
  exit 2
fi
if [ ! -f pubspec.yaml ]; then
  echo "round-gate.sh: a repó gyökeréből futtasd (nincs pubspec.yaml itt)" >&2
  exit 2
fi
if [ "$#" -eq 0 ]; then
  echo "használat: tools/round-gate.sh <teszt-útvonal> [további teszt-útvonal ...]" >&2
  echo "  a kör által ÉRINTETT terület tesztjei; a teljes suite a CI-ban fut (ADR 0053)" >&2
  exit 2
fi

step_number=0
declare -a step_names=()
declare -a step_results=()

run_step() {
  local name=$1
  shift
  step_number=$((step_number + 1))
  echo
  echo "═══ [$step_number] $name"
  echo "    \$ $*"
  echo
  # Külön processz, csonkítatlan kimenet, nincs csővezeték.
  "$@"
  local code=$?
  step_names+=("$name")
  if [ "$code" -eq 0 ]; then
    step_results+=("zöld")
    echo
    echo "    → [$step_number] $name: ZÖLD"
  else
    step_results+=("PIROS ($code)")
    echo
    echo "    → [$step_number] $name: PIROS (kilépési kód $code)" >&2
    summary
    exit "$code"
  fi
  # A következő lépés friss processzben induljon (analyze/test memória, L05).
  sleep 2
}

summary() {
  echo
  echo "═══ Gate-összegzés"
  local index=0
  while [ "$index" -lt "${#step_names[@]}" ]; do
    printf '    %-58s %s\n' "${step_names[$index]}" "${step_results[$index]}"
    index=$((index + 1))
  done
}

run_step "format" \
  "$dart_bin" format --output=none --set-exit-if-changed lib test tool

run_step "analyze" \
  "$flutter_bin" analyze lib/ test/ tool/

for test_path in "$@"; do
  run_step "test $test_path" "$flutter_bin" test "$test_path"
done

run_step "architecture" \
  "$dart_bin" run tool/check_architecture.dart

summary
echo
echo "MINDEN GATE ZÖLD. A teljes suite + randomizált property gate + APK a CI-ban"
echo "fut (ADR 0053) — azt az orchestrátor indítja, te ne hívj gh-t."
