#!/usr/bin/env bash
# Kör-gate futtató (ADR 0052 zöld kapu, AGENTS.md §12).
#
#   tools/round-gate.sh [--result-json PATH] <teszt-útvonal> [...]
#
# ROUND_GATE_RESULT_FILE ugyanazt a strukturált kimenetet kéri, mint a
# --result-json. A lépések külön processzekben futnak; nincs shell-eval,
# parancslánc vagy a valódi kilépési kódot elrejtő pipe.
#
# Kilépési kódok:
#   0  = pass
#   10 = code_failure
#   20 = environment_failure
#   30 = invalid_gate
#   40 = internal_failure
set -uo pipefail

flutter_bin=${FLUTTER_BIN:-$HOME/flutter/bin/flutter}
dart_bin=${DART_BIN:-$HOME/flutter/bin/dart}
sleep_seconds=${ROUND_GATE_SLEEP_SECONDS:-2}
result_file=${ROUND_GATE_RESULT_FILE:-}

if [ "${1:-}" = "--result-json" ]; then
  if [ "$#" -lt 2 ]; then
    echo "round-gate.sh: a --result-json értéke kötelező" >&2
    exit 30
  fi
  result_file=$2
  shift 2
fi

write_result() {
  [ -n "$result_file" ] || return 0
  local outcome=$1 exit_code=$2 failed_step=${3:-} command_exit=${4:-0} error_hash=${5:-}
  python3 -c '
import json, os, pathlib, sys, tempfile
path = pathlib.Path(sys.argv[1])
payload = {
    "schema_version": 1,
    "outcome": sys.argv[2],
    "exit_code": int(sys.argv[3]),
    "failed_step": sys.argv[4] or None,
    "command_exit_code": int(sys.argv[5]),
    "error_hash": sys.argv[6] or None,
}
path.parent.mkdir(parents=True, exist_ok=True)
fd, temporary = tempfile.mkstemp(prefix=path.name + ".", dir=path.parent)
try:
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, ensure_ascii=False, sort_keys=True)
        handle.write("\n")
        handle.flush()
        os.fsync(handle.fileno())
    os.chmod(temporary, 0o600)
    os.replace(temporary, path)
except BaseException:
    try:
        os.unlink(temporary)
    except FileNotFoundError:
        pass
    raise
' "$result_file" "$outcome" "$exit_code" "$failed_step" "$command_exit" "$error_hash"
}

finish_error() {
  local outcome=$1 router_exit=$2 message=$3 failed_step=${4:-} command_exit=${5:-0}
  echo "round-gate.sh: $message" >&2
  local fingerprint hash
  fingerprint=$(mktemp)
  printf '%s\n%s\n%s\n' "$outcome" "$failed_step" "$command_exit" > "$fingerprint"
  hash=$(sha256sum "$fingerprint")
  hash=${hash%% *}
  rm -f "$fingerprint"
  if ! write_result "$outcome" "$router_exit" "$failed_step" "$command_exit" "sha256:$hash"; then
    echo "round-gate.sh: az eredményfájl nem írható" >&2
    exit 40
  fi
  exit "$router_exit"
}

if [ ! -x "$flutter_bin" ] || [ ! -x "$dart_bin" ]; then
  finish_error "environment_failure" 20 \
    "nincs futtatható flutter/dart ($flutter_bin, $dart_bin)" "preflight.tools" 2
fi
if [ ! -f pubspec.yaml ]; then
  finish_error "environment_failure" 20 \
    "a repó gyökeréből futtasd (nincs pubspec.yaml itt)" "preflight.repository" 2
fi
if [ "$#" -eq 0 ]; then
  finish_error "invalid_gate" 30 \
    "legalább egy célzott tesztútvonal kötelező" "preflight.arguments" 2
fi

for test_path in "$@"; do
  case "$test_path" in
    "" | -* | /* | *"/../"* | ../* | */..)
      finish_error "invalid_gate" 30 \
        "érvénytelen tesztútvonal: $test_path" "preflight.arguments" 2
      ;;
  esac
done

step_number=0
declare -a step_names=()
declare -a step_results=()
gate_tmp=$(mktemp -d)
trap 'rm -rf "$gate_tmp"' EXIT

summary() {
  echo
  echo "═══ Gate-összegzés"
  local index=0
  while [ "$index" -lt "${#step_names[@]}" ]; do
    printf '    %-58s %s\n' "${step_names[$index]}" "${step_results[$index]}"
    index=$((index + 1))
  done
}

run_step() {
  local name=$1
  shift
  step_number=$((step_number + 1))
  local step_log="$gate_tmp/step-$step_number.log"
  echo
  echo "═══ [$step_number] $name"
  printf '    $'
  printf ' %q' "$@"
  echo
  echo
  "$@" >"$step_log" 2>&1
  local code=$?
  cat "$step_log"
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
    local digest
    digest=$(sha256sum "$step_log")
    digest=${digest%% *}
    if ! write_result "code_failure" 10 "$name" "$code" "sha256:$digest"; then
      echo "round-gate.sh: az eredményfájl nem írható" >&2
      exit 40
    fi
    exit 10
  fi
  if [ "$sleep_seconds" != "0" ]; then
    sleep "$sleep_seconds"
  fi
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
if ! write_result "pass" 0 "" 0 ""; then
  echo "round-gate.sh: az eredményfájl nem írható" >&2
  exit 40
fi
