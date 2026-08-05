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
baseline_mode=0

if [ "${1:-}" = "--result-json" ]; then
  if [ "$#" -lt 2 ]; then
    echo "round-gate.sh: a --result-json értéke kötelező" >&2
    exit 30
  fi
  result_file=$2
  shift 2
fi

if [ "${1:-}" = "--baseline" ]; then
  baseline_mode=1
  shift
fi

# --- Backend sáv (ADR 0173) ----------------------------------------------
# MÉRT hiányosság: a gate Dart-only volt, ezért a backendet érintő körök
# Python-oldali mércéje CSAK a CI-ban futott. Ez körönként egy teljes javító
# kört jelentett (E04-R15 MAJOR-1: `ruff check` zöld, `ruff format --check`
# piros → Backend CI piros; E04-R14: pytest-hibák csak a friss CI-checkouton).
#
# A sáv MAGÁTÓL kapcsol be, ha a kör hozzáért a `backend/`-hez — nincs
# kapcsoló a kihagyására, mert az a mérce gyengítése lenne.
backend_touched() {
  [ -d backend ] || return 1
  if [ -n "$(git status --porcelain -- backend 2>/dev/null)" ]; then
    return 0
  fi
  local base
  base=$(git merge-base HEAD origin/main 2>/dev/null) || return 1
  [ -n "$base" ] || return 1
  [ -n "$(git diff --name-only "$base" HEAD -- backend 2>/dev/null)" ]
}

# A munkapéldányokban nincs saját `backend/.venv` (gitignore-olt), ezért a
# fő repó venv-je is elfogadott: az interpreter csak a függőségeket hozza, a
# MÉRT fájlok a munkapéldányból jönnek (cwd elsőbbség a sys.path-on).
resolve_backend_python() {
  local candidate
  for candidate in \
    "${ROUND_GATE_BACKEND_PYTHON:-}" \
    "backend/.venv/bin/python" \
    "$HOME/music-theory/backend/.venv/bin/python"; do
    [ -n "$candidate" ] && [ -x "$candidate" ] && { printf '%s\n' "$candidate"; return 0; }
  done
  return 1
}

if [ "${1:-}" = "--backend-plan" ]; then   # teszthorog: futna-e a backend sáv
  if backend_touched; then echo run; else echo skip; fi
  exit 0
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
if [ "$#" -eq 0 ] && [ "$baseline_mode" -ne 1 ]; then
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

# --- Globális gate-zár (ADR 0171 §1) -------------------------------------
# A gate ezen a boxon a MEMÓRIA szűk keresztmetszete (docs/LESSONS.md L05: az
# `analyze && test` lánc OOM-ot okoz). Ha egyszerre több kör fut
# (PIPELINE_SLOTS>1), a gate-jeik akkor sem futhatnak egyidejűleg.
#
# Ez a zár SOROSÍT, nem lazít: egyetlen lépést sem hagy ki, egyetlen küszöböt
# sem mozdít, csak megvárja a másik gate-futás végét. A mérce változatlan —
# a párhuzamosság a körök KÖZÖTT van, nem a gate-en belül.
#
#   ROUND_GATE_LOCK=none         → kikapcsolva (mérés/teszt)
#   ROUND_GATE_LOCK_WAIT=<mp>    → felső várakozási korlát (alap: 90 perc)
gate_lock=${ROUND_GATE_LOCK:-${TMPDIR:-/tmp}/strumsight-round-gate.lock}
gate_lock_wait=${ROUND_GATE_LOCK_WAIT:-5400}
if [ "$gate_lock" != "none" ] && [ -w "$(dirname "$gate_lock")" ] && command -v flock >/dev/null 2>&1; then
  exec 8>"$gate_lock"
  if ! flock -w "$gate_lock_wait" 8; then
    finish_error "environment_failure" 20 \
      "egy másik gate-futás ${gate_lock_wait}s után is tartja a zárat ($gate_lock)" "preflight.lock" 2
  fi
fi

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

# Titok-scan (ADR 0138): az AGENTS.md §5 „secret nem kerülhet commitba" határa
# eddig gépi őr nélkül állt. Csak a git által KÖVETETT fájlokat nézi.
run_step "secrets" \
  "$dart_bin" run tool/ci/check_secrets.dart

# Lokalizációs paritás (ADR 0138): az ARCH-008 mechanikus fele — minden
# sablon-kulcsnak van nem üres, azonos helyőrzőjű fordítása.
run_step "l10n" \
  "$dart_bin" run tool/ci/check_l10n_parity.dart

# Backend sáv (ADR 0173): ugyanaz a három lépés, amit a Backend CI futtat —
# csak most a kör VÉGÉN, nem a merge-kapunál derül ki, ha piros.
if backend_touched; then
  if ! backend_python=$(resolve_backend_python); then
    finish_error "environment_failure" 20 \
      "a kör a backendhez ért, de nincs backend venv (backend/README.md: python3 -m venv backend/.venv && .venv/bin/pip install -r requirements-dev.txt)" \
      "preflight.backend" 2
  fi
  run_step "backend ruff format" "$backend_python" -m ruff format --check backend/app backend/tests
  run_step "backend ruff check" "$backend_python" -m ruff check backend/app backend/tests
  run_step "backend pytest" env --chdir=backend "$backend_python" -m pytest -q
fi

summary
echo
echo "MINDEN GATE ZÖLD. A teljes suite + randomizált property gate + APK a CI-ban"
echo "fut (ADR 0053) — azt az orchestrátor indítja, te ne hívj gh-t."
if ! write_result "pass" 0 "" 0 ""; then
  echo "round-gate.sh: az eredményfájl nem írható" >&2
  exit 40
fi
