#!/usr/bin/env bash
# Kör-indító burkoló a Codexhez (AGENTS.md §15.3).
#
#   tools/codex-round.sh <munkapéldány> <prompt-fájl> [logfájl]
#
# Miért nem `codex exec` közvetlenül: a burkoló GARANTÁLJA, hogy a futás
# véget ér és nyomot hagy — akkor is, ha a Codex elszáll, beragad, vagy
# elfelejt jelezni. Az orchestrátor (Claude) ezt háttér-taskként indítja, így
# a harness a folyamat kilépésekor automatikusan értesíti.
#
# Három védelmi vonal (user-szabály 2026-07-29: "ne várjunk rá fél napot"):
#   1. Codex-oldali jelzés            → tools/codex-signal.sh (§15.2)
#   2. elakadás-őr (a log nem nő)     → CODEX_STALL_MINUTES, alapértelmezés 12
#   3. abszolút időkorlát             → CODEX_ROUND_TIMEOUT, alapértelmezés 3600s
#
# Kilépési kód: 0 = a Codex rendben kilépett, 1 = elakadás/időtúllépés miatt
# lőttük ki, egyéb = a Codex saját kilépési kódja.
set -uo pipefail

workdir=${1:?használat: codex-round.sh <munkapéldány> <prompt-fájl> [logfájl]}
prompt_file=${2:?használat: codex-round.sh <munkapéldány> <prompt-fájl> [logfájl]}
log_file=${3:-/tmp/codex-$(basename "$workdir").log}

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# --- Motor-profil (ADR 0139) ---------------------------------------------
# A motorok kvótája külön merül ki, ezért a profilok egymás mellett élnek és a
# váltás egyetlen fájl (`tools/engine-profile.sh use <name>`). Sorrend:
#   1. ROUND_ENGINE (a hívó explicit döntése)
#   2. az aktív override (engine-profile.sh use)
#   3. terra (a történeti alapértelmezés: az ambiens ~/.codex)
round_engine=${ROUND_ENGINE:-}
if [ -z "$round_engine" ]; then
  round_engine=$(bash "$script_dir/engine-profile.sh" show 2>/dev/null)
  case "$round_engine" in *'<'*|'') round_engine=terra ;; esac
fi

engine_env=$(bash "$script_dir/engine-profile.sh" env "$round_engine" 2>/dev/null) || {
  echo "codex-round.sh: ismeretlen motor: $round_engine" >&2
  exit 2
}
while IFS='=' read -r key value; do
  [ -n "$key" ] && export "$key=$value"
done <<< "$engine_env"

# Codex-harness kötelező: a claude-harness motorokat a mm-round.sh viszi.
case "$(grep -m1 "^${round_engine}	" "$script_dir/../docs/execution/engine-registry.tsv" | cut -f2)" in
  codex) ;;
  *) echo "codex-round.sh: a(z) $round_engine motor nem Codex-harness — használd az mm-round.sh-t" >&2; exit 2 ;;
esac

# A LASSÚ motor (pl. Qwen ~95 s/válasz) hamis elakadásnak látszana a 12 perces
# alapértelmezéssel, ezért a nyilvántartás motoronként adja meg a küszöböket.
stall_minutes=${CODEX_STALL_MINUTES:-${ENGINE_STALL_MINUTES:-12}}
round_timeout=${CODEX_ROUND_TIMEOUT:-${ENGINE_ROUND_TIMEOUT:-3600}}
signal="$workdir/.codex-round-status"
echo "codex-round.sh: motor=$round_engine modell=${ENGINE_MODEL:-?} stall=${stall_minutes}p timeout=${round_timeout}s" >&2

rm -f "$signal"
: > "$log_file"

# A scope-audit (ADR 0138) BÁZISA: a munkapéldány HEAD-je az indítás
# pillanatában. Nem az `origin/main`, mert az orchestrátor pre-flight commitja
# (kör-ADR + brief-revízió) jogosan nyúl az allowed_paths-on kívülre — innen
# mérve a verdikt az IMPLEMENTER saját munkájára szól.
scope_base=$(git -C "$workdir" rev-parse HEAD 2>/dev/null)

# A modellt és a kontextus-korlátokat a nyilvántartás adja, nem a profil:
# egyetlen Kilo-profil (`~/.codex-kilo`) mögött több modell is él, és a
# Kilo /responses NEM ad model-metaadatot — a túlbecsült ablak
# kontextus-túlcsordulást okozna.
codex_model_args=()
[ -n "${ENGINE_MODEL:-}" ] && codex_model_args+=(-m "$ENGINE_MODEL")
[ -n "${ENGINE_CONTEXT_WINDOW:-}" ] && codex_model_args+=(-c "model_context_window=$ENGINE_CONTEXT_WINDOW")
[ -n "${ENGINE_MAX_OUTPUT:-}" ] && codex_model_args+=(-c "model_max_output_tokens=$ENGINE_MAX_OUTPUT")

# `< /dev/null`: enélkül a codex exec a promptot megkapva IS stdin-re vár
# ("Reading additional input from stdin"), és a kör némán beragad.
codex exec -C "$workdir" -s danger-full-access \
  "${codex_model_args[@]}" "$(cat "$prompt_file")" < /dev/null \
  >> "$log_file" 2>&1 &
codex_pid=$!

started=$(date +%s)
killed_reason=""

while kill -0 "$codex_pid" 2>/dev/null; do
  sleep 20
  now=$(date +%s)
  log_age=$(( now - $(stat -c %Y "$log_file") ))

  if [ $(( now - started )) -ge "$round_timeout" ]; then
    killed_reason="timeout"
  elif [ "$log_age" -ge $(( stall_minutes * 60 )) ]; then
    # A log percek óta nem nőtt: a Codex vár valamire, ami nem fog megjönni.
    killed_reason="stalled"
  fi

  if [ -n "$killed_reason" ]; then
    kill "$codex_pid" 2>/dev/null || true
    sleep 5
    kill -9 "$codex_pid" 2>/dev/null || true
    break
  fi
done

wait "$codex_pid" 2>/dev/null
exit_code=$?

if [ -n "$killed_reason" ]; then
  # A saját jelzését felülírjuk: a tény az, hogy kilőttük.
  {
    echo "status=$killed_reason"
    if [ "$killed_reason" = "stalled" ]; then
      echo "summary=a log ${stall_minutes} percig nem nőtt — a futást kilőttük"
    else
      echo "summary=elérte a ${round_timeout}s abszolút időkorlátot — a futást kilőttük"
    fi
    echo "branch=$(git -C "$workdir" branch --show-current)"
    echo "head=$(git -C "$workdir" rev-parse --short HEAD)"
    echo "dirty_files=$(git -C "$workdir" status --porcelain | wc -l | tr -d ' ')"
    echo "signalled_at=$(date -Iseconds)"
  } > "$signal"
  exit_code=1
elif [ ! -f "$signal" ] || ! grep -qE '^status=(done|stopped|blocked)$' "$signal"; then
  # Kilépett, de nem zárta le magát: összeomlás, kill, vagy figyelmen kívül
  # hagyta a §15.2 jelzési szabályt. Az orchestrátor sosem találgat.
  {
    echo "status=unknown"
    echo "summary=a Codex lezáró jelzés nélkül lépett ki (exit ${exit_code}) — nézd meg: ${log_file}"
    echo "branch=$(git -C "$workdir" branch --show-current)"
    echo "head=$(git -C "$workdir" rev-parse --short HEAD)"
    echo "dirty_files=$(git -C "$workdir" status --porcelain | wc -l | tr -d ' ')"
    echo "signalled_at=$(date -Iseconds)"
  } > "$signal"
fi

# Scope-audit (ADR 0138): a gépi verdikt a jelzésfájlba kerül, mielőtt az
# orchestrátor bármit olvasna. Sértéskor a jelzés `stopped`-ra vált.
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
bash "$script_dir/round-scope-audit.sh" "$workdir" "$scope_base" "$signal"
scope_exit=$?
[ "$scope_exit" -eq 1 ] && exit_code=1

echo "--- codex round finished ---"
echo "log: $log_file"
cat "$signal"
exit "$exit_code"
