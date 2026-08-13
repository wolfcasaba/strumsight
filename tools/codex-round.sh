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

# Self-heal E06-R07/H7 (docs/LESSONS.md L221): ha a munkapéldányt a hub
# lokális útvonaláról klónozták (SKILL.md §3 `git clone <hub> <cél>`), az
# `origin` a hub útvonalára mutat — ha a hub épp a kör branch-én áll, egy
# implementer-push `receive.denyCurrentBranch`-sel elutasul. A javítás a
# munkapéldány indulásakor, MIELŐTT az implementer bármit commitolna, az
# origin-t a hub SAJÁT upstream-jére állítja (fail-open no-op, ha nincs mit
# javítani).
bash "$script_dir/fix-workspace-origin.sh" "$workdir" >&2 || true

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

has_terminal_signal() { grep -qE '^status=(done|stopped|blocked)$' "$signal" 2>/dev/null; }

# MÉRT hibaminta (E06-R23 self-heal, ADR 0112, 2026-08-12): a Codex a saját
# STOP-protokollja szerint helyesen megírta a jelzésfájlt (`status=stopped`,
# scope-sértés), de utána a folyamat NEM ért véget — a modell tovább
# dolgozott, és MÉG HAT további commitot hozott létre percekkel a jelzés
# UTÁN, mielőtt a forduló magától kilépett. A jelzésfájl írása eddig csak azt
# garantálta, hogy az orchestrátor `wait-for-round.sh`-ja észreveszi a
# terminális állapotot — a folyamatot magát semmi nem állította le. A
# ciklus ezért a `killed_reason`-nel egyenrangúan figyeli a jelzésfájlt is:
# ha AZ ALATT jelenik meg egy terminális státusz, amíg a Codex még fut, a
# burkoló ugyanazzal a kilövési szekvenciával zár, mint elakadásnál/
# időtúllépésnél — de KÜLÖN jelzővel (`terminal_signal_seen`), hogy a
# `killed_reason`-re épülő, alább következő „a jelzést felülírjuk" ág ne
# írja felül a Codex SAJÁT, helyes jelentését.
run_attempt() {   # $@ = a codex parancs argumentumai
  local codex_pid now log_age terminal_signal_seen
  "$@" < /dev/null >> "$log_file" 2>&1 &
  codex_pid=$!
  terminal_signal_seen=""
  while kill -0 "$codex_pid" 2>/dev/null; do
    sleep "$poll_seconds"
    now=$(date +%s)
    log_age=$(( now - $(stat -c %Y "$log_file") ))
    if [ "$now" -ge "$deadline" ]; then
      killed_reason="timeout"
    elif [ "$log_age" -ge $(( stall_minutes * 60 )) ]; then
      # A log percek óta nem nőtt: a Codex vár valamire, ami nem fog megjönni.
      killed_reason="stalled"
    elif has_terminal_signal; then
      terminal_signal_seen=1
    fi
    if [ -n "$killed_reason" ] || [ -n "$terminal_signal_seen" ]; then
      kill "$codex_pid" 2>/dev/null || true
      sleep 1
      kill -9 "$codex_pid" 2>/dev/null || true
      break
    fi
  done
  wait "$codex_pid" 2>/dev/null
  exit_code=$?
}

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

# --- Költség-főkönyv (ADR 0174) -------------------------------------------
# A modell a saját naplójába írja az elhasznált tokent („tokens used\n<szám>"),
# a motor árát pedig a nyilvántartás tartalmazza — de a kettő eddig SEHOL nem
# találkozott, ezért a motorválasztás volt a leggyengébben alátámasztott
# döntésünk. A főkönyv egy sor/futás, és túléli a /tmp naplókat.
#
# Fail-open: ha a főkönyv könyvtára nem létezik (teszt, idegen box), néma no-op.
record_cost() {
  local ledger=${PIPELINE_COST_LEDGER:-"$HOME/music-theory/.pipeline/cost.tsv"}
  [ -d "$(dirname "$ledger")" ] || return 0
  local tokens round status
  tokens=$(grep -A1 -i '^tokens used' "$log_file" 2>/dev/null | tail -1 | tr -cd '0-9')
  [ -n "$tokens" ] || tokens=0
  round=$(printf '%s' "${ROUND_BRIEF:-$(git -C "$workdir" branch --show-current 2>/dev/null)}" \
    | grep -oiE '[e][0-9]{2}-[r][0-9]{2}' | head -1 | tr 'a-z' 'A-Z')
  [ -n "$round" ] || round="ismeretlen"
  status=$(grep -m1 '^status=' "$signal" 2>/dev/null | cut -d= -f2-)
  [ -f "$ledger" ] || printf 'timestamp\tround\tengine\tmodel\ttokens\tcontinuations\tstatus\n' > "$ledger"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(date -Is)" "$round" "$round_engine" "${ENGINE_MODEL:-?}" \
    "$tokens" "$continuations" "${status:-ismeretlen}" >> "$ledger"
}
record_cost

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

# --- Anti-hallucináció őrök (2026-08-06, MÉRT M3-hibaminták) --------------
# A szöveges tiltás nála bizonyítottan nem tart (E02-R07: háromszor futtatta a
# gate-et `| tail` mögé a brief explicit tiltása ellenére), ezért a jelzésbe
# GÉPI megfigyelés kerül — a reviewer így nem az állítást olvassa, hanem a mért
# tényt.
#
# 1. `done` munka NÉLKÜL: ha a fa nem mozdult az indulás óta (nincs új commit
#    ÉS nincs diff), a „kész" jelentés hamis állítás — `unknown`-ra váltjuk,
#    kivéve ha a hívó explicit `ROUND_VERIFY_NOOP_OK=1`-gyel vállalja (lásd lent).
# 2. Gate-alak: a naplóban keressük a csonkoló/láncoló gate-hívást.
verify_claim() {
  local head_now dirty gate_shape
  head_now=$(git -C "$workdir" rev-parse HEAD 2>/dev/null)
  # A burkoló SAJÁT artefaktumai (jelzésfájl, pid-fájl) nem számítanak munkának
  # — nélkülük a „piszkos fa" mindig igaz lenne, és az őr sosem sülne el.
  dirty=$(git -C "$workdir" status --porcelain -- . \
    ':(exclude).codex-round-status' ':(exclude).mm-round-pid' | wc -l | tr -d " ")
  if grep -qE '^status=done$' "$signal" 2>/dev/null \
    && [ "$head_now" = "$scope_base" ] && [ "$dirty" = "0" ]; then
    if [ "${ROUND_VERIFY_NOOP_OK:-0}" = "1" ]; then
      # Self-heal E06-R27/H6 (docs/LESSONS.md L263, 2026-08-13): egy javító
      # forduló valódi munkát commitolt (524397de), de jelzés nélkül lépett ki
      # (lásd az elif ágat feljebb — `status=unknown`, "lezáró jelzés
      # nélkül"). Az emiatt dispatch-elt, KIZÁRÓLAG megerősítésre/újra-
      # jelzésre kért következő forduló jogosan állított `done`-t új
      # commit/diff NÉLKÜL — az ő invokáció-kezdő `scope_base`-e MÁR a
      # korábbi forduló valódi munkáját tartalmazta, csak az ÉPP FUTÓ
      # invokáción belül nem mozdult tovább (ez a feladat lényege, nem
      # hallucináció). A dispatchernek ezt EXPLICITEN kell vállalnia — az
      # implementer önbevallása önmagában nem bizonyíték, csak a hívó saját,
      # ellenőrzött döntése.
      printf 'verify_noop_ok=1\n' >> "$signal"
    else
      {
        echo "status=unknown"
        echo "summary=a jelzés done volt, de a munkapéldány NEM mozdult (nincs commit, nincs diff) — a kész jelentés bizonyítatlan"
        echo "branch=$(git -C "$workdir" branch --show-current)"
        echo "head=$head_now"
        echo "dirty_files=0"
        echo "signalled_at=$(date -Iseconds)"
      } > "$signal"
      exit_code=1
    fi
  fi
  gate_shape=ok
  if grep -qE "round-gate\.sh[^\n]*(\| *(tail|head)|&&)" "$log_file" 2>/dev/null; then
    gate_shape=VIOLATION
  fi
  grep -q "^gate_shape=" "$signal" 2>/dev/null || printf 'gate_shape=%s\n' "$gate_shape" >> "$signal"
}
verify_claim

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
