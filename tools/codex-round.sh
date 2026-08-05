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

# --- Motor-profil (ADR 0140) ---------------------------------------------
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
# Gondolkodási szint motoronként (ADR 0173). MÉRVE 2026-08-05: a Kilo-profil
# alatt futó Qwenek fejlécében `reasoning effort: none` állt — egy $2/$6-os
# modellt gondolkodás nélkül futtattunk. A provider elfogadja a paramétert
# (füst-teszt: qwen3.8-max + medium → sikeres szerkesztés).
[ -n "${ENGINE_REASONING:-}" ] && [ "${ENGINE_REASONING}" != "-" ] \
  && codex_model_args+=(-c "model_reasoning_effort=$ENGINE_REASONING")

codex_bin=${CODEX_BIN:-codex}

# --- Implementer-preambulum (ADR 0173) ------------------------------------
# A mért hibaminták tiltása NEM maradhat körönként kézzel újraírt prompt-szöveg
# (az E04-R16 orchestrátora már kézzel figyelmeztetett a „bejelent és kilép"
# mintára). A preambulum artefaktum: minden Codex-harness kör MINDEN
# fordulója ezt kapja a feladat elé.
preamble_file="$script_dir/../docs/execution/implementer-preamble.md"
prompt_text=$(cat "$prompt_file")
if [ "${CODEX_NO_PREAMBLE:-0}" != "1" ] && [ -f "$preamble_file" ]; then
  prompt_text=$(printf '%s\n\n---\n\n%s' "$(cat "$preamble_file")" "$prompt_text")
fi

# --- Egy forduló futtatása őrökkel ----------------------------------------
# A `killed_reason` és az `exit_code` a hívóhoz szól. A globális határidő az
# EGÉSZ körre vonatkozik, tehát a folytatások is beleférnek — a folytatás nem
# nyithat új időkeretet.
deadline=$(( $(date +%s) + round_timeout ))
killed_reason=""
exit_code=0

# Az őr-ciklus mintavételi ideje. Éles körben 20 s (a modell perceket
# gondolkodik, sűrűbb mintavétel értelmetlen); a tesztek 1-re állítják, hogy a
# suite ne várakozással teljen.
poll_seconds=${CODEX_POLL_SECONDS:-20}

run_attempt() {   # $@ = a codex parancs argumentumai
  local codex_pid now log_age
  "$@" < /dev/null >> "$log_file" 2>&1 &
  codex_pid=$!
  while kill -0 "$codex_pid" 2>/dev/null; do
    sleep "$poll_seconds"
    now=$(date +%s)
    log_age=$(( now - $(stat -c %Y "$log_file") ))
    if [ "$now" -ge "$deadline" ]; then
      killed_reason="timeout"
    elif [ "$log_age" -ge $(( stall_minutes * 60 )) ]; then
      # A log percek óta nem nőtt: a Codex vár valamire, ami nem fog megjönni.
      killed_reason="stalled"
    fi
    if [ -n "$killed_reason" ]; then
      kill "$codex_pid" 2>/dev/null || true
      sleep 1
      kill -9 "$codex_pid" 2>/dev/null || true
      break
    fi
  done
  wait "$codex_pid" 2>/dev/null
  exit_code=$?
}

has_terminal_signal() { grep -qE '^status=(done|stopped|blocked)$' "$signal" 2>/dev/null; }

# A session-azonosítót a Codex a saját fejlécébe írja („session id: <uuid>"),
# ezért a folytatáshoz nem kell külön állapotot vezetnünk.
session_id_from_log() {
  grep -m1 -oE '^session id: [0-9a-f-]{36}' "$log_file" 2>/dev/null | awk '{print $3}'
}

# `< /dev/null`: enélkül a codex exec a promptot megkapva IS stdin-re vár
# ("Reading additional input from stdin"), és a kör némán beragad.
run_attempt "$codex_bin" exec -C "$workdir" -s danger-full-access \
  "${codex_model_args[@]}" "$prompt_text"

# --- Automatikus folytatás (ADR 0173) -------------------------------------
# MÉRT hibaminta (E04-R13, E04-R14, E04-R16 mindkét kísérlete): a modell a
# fordulót a KÖVETKEZŐ LÉPÉS BEJELENTÉSÉVEL zárja („Now the action confirmation
# service…", „First Flutter compile is slow — waiting…"), a harness pedig
# kilép, mert a modell záró üzenetet küldött tool-hívás helyett. A munka
# félkész, a jelzés hiányzik, és eddig ez EGY TELJES kör-újraindítás volt.
#
# A folytatás ugyanabban a session-ben megy (`codex exec resume <id>`), ezért a
# kontextus megmarad — nem újrakezdés, hanem továbbvitel. Csak akkor indul, ha
# a forduló MAGÁTÓL ért véget jelzés nélkül: elakadás/időtúllépés után nem,
# mert ott a kilövés a tény.
max_continuations=${CODEX_MAX_CONTINUATIONS:-2}
continuations=0
continuation_prompt=${CODEX_CONTINUATION_PROMPT:-"FOLYTATÁS (automatikus, a burkoló küldi). Az előző fordulód munka közben ért véget: bejelentetted a következő lépést, de nem hajtottad végre, és nem zártad le a kört. NE tervezz és NE jelents be lépéseket. MOST, ebben a sorrendben: (1) folytasd pontosan ott, ahol abbahagytad, és írd meg a hátralévő fájlokat; (2) git add -A && git commit a kör branchére; (3) futtasd a kör gate-jét az eredeti feladat szerint; (4) zárd le: tools/codex-signal.sh done|stopped|blocked \"<egy sor>\". A forduló CSAK a jelzéssel ér véget — a bejelentés nem munka."}

while [ -z "$killed_reason" ] && ! has_terminal_signal \
  && [ "$continuations" -lt "$max_continuations" ] \
  && [ "$(date +%s)" -lt $(( deadline - 120 )) ]; do
  session_id=$(session_id_from_log)
  [ -n "$session_id" ] || { echo "codex-round.sh: nincs session-id a logban — folytatás nem lehetséges" >&2; break; }
  log_size_before=$(stat -c %s "$log_file")
  continuations=$(( continuations + 1 ))
  echo "codex-round.sh: jelzés nélküli forduló-vég — automatikus folytatás #$continuations (session $session_id)" >&2
  printf '\n--- codex-round.sh: automatikus folytatás #%s ---\n' "$continuations" >> "$log_file"
  # A `resume` NEM ismeri a `-C`/`-s` kapcsolót: a munkakönyvtárat a session
  # hozza magával, a sandbox-feloldást pedig a bypass-kapcsoló adja.
  run_attempt env --chdir="$workdir" "$codex_bin" exec resume "$session_id" \
    -m "${ENGINE_MODEL:-}" --dangerously-bypass-approvals-and-sandbox \
    "$continuation_prompt"
  if [ "$(stat -c %s "$log_file")" -le "$log_size_before" ]; then
    echo "codex-round.sh: a folytatás nem termelt kimenetet — nem próbálkozunk tovább" >&2
    break
  fi
done

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

# A folytatások száma a REVIEW bemenete (ADR 0173): egy `done`, amelyhez két
# automatikus folytatás kellett, nem ugyanaz a bizonyíték, mint egy egy
# fordulóban lezárt kör — a reviewer így látja, hol volt szakadás.
if [ -f "$signal" ] && ! grep -q '^continuations=' "$signal"; then
  {
    printf 'continuations=%s\n' "$continuations"
    session_for_signal=$(session_id_from_log)
    [ -n "$session_for_signal" ] && printf 'session_id=%s\n' "$session_for_signal"
  } >> "$signal"
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
