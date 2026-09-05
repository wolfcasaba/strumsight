#!/usr/bin/env bash
# Kör-indító burkoló a MiniMax M3 implementerhez (AGENTS.md §15.3, ADR 0069).
#
#   tools/mm-round.sh <munkapéldány> <prompt-fájl> [logfájl]
#
# Ugyanaz a szerződés, mint a tools/codex-round.sh-nál — csak a motor más:
# a Claude Code harness fut, IZOLÁLT config dir-rel (CLAUDE_CONFIG_DIR), hogy az
# orchestrátor Claude saját konfigját és auth-ját ne érintse.
#
# KÉT ÜZEMMÓD (ADR 0140 nyilvántartás-vezérelt, 2026-08-06):
#   * külső Anthropic-kompatibilis endpoint (MiniMax M3): a nyilvántartás
#     `auth_env`/`auth_file` mezője megadja a kulcsot → ANTHROPIC_BASE_URL +
#     ANTHROPIC_AUTH_TOKEN a MiniMax `/anthropic` endpointjára;
#   * natív Claude-modell az ELŐFIZETÉSEN (pl. claude-sonnet-5 implementerként):
#     a nyilvántartásban `auth_env`/`auth_file` = `-`, ilyenkor NINCS
#     base-url/token override, a config dir saját auth-ja dönt.
# A modellt, a config dirt és az őr-küszöböket a nyilvántartás adja, ha
# ROUND_ENGINE be van állítva; enélkül a történeti MiniMax-alapértelmezés él.
#
# Három védelmi vonal (user-szabály 2026-07-29: "ne várjunk rá fél napot"):
#   1. implementer-oldali jelzés      → tools/codex-signal.sh (§15.2, közös)
#   2. elakadás-őr (a log nem nő)     → MM_STALL_MINUTES, alapértelmezés 5
#   3. abszolút időkorlát             → MM_ROUND_TIMEOUT, alapértelmezés 3600s
#
# MIÉRT stream-json a kimeneti formátum: a sima `claude -p` MINDENT a futás
# végén ír ki, így a log mérete addig 0 marad — egy log-alapú elakadás-őr ezzel
# minden hosszabb kört tévesen kilőne. A stream-json eseményenként ír, tehát a
# log folyamatosan nő, és a watcher látja, épp melyik tool fut.
#
# Kontextus: a MiniMax `/v1/models` nem ad vissza `context_window` mezőt, ezért
# a Claude Code a beépített 200K-s alapértelmezésre esne vissza és ~167K-nál
# idő előtt compact-olna. A CLAUDE_CODE_AUTO_COMPACT_WINDOW=1000000 ezt oldja
# fel — az endpoint mérten elfogad 498K input tokent (2026-07-30).
#
# Kilépési kód: 0 = rendben kilépett, 1 = elakadás/időtúllépés miatt lőttük ki,
# egyéb = a futás saját kilépési kódja.
set -uo pipefail

workdir=${1:?használat: mm-round.sh <munkapéldány> <prompt-fájl> [logfájl]}
prompt_file=${2:?használat: mm-round.sh <munkapéldány> <prompt-fájl> [logfájl]}
log_file=${3:-/tmp/mm-$(basename "$workdir").log}

# A prompt-fájlt még a munkapéldányba lépés ELŐTT abszolutizáljuk, különben a
# relatív útvonal az alhéjban már máshova mutatna.
prompt_file=$(readlink -f "$prompt_file")
workdir=$(readlink -f "$workdir")

if [ ! -f "$prompt_file" ]; then
  echo "mm-round.sh: a prompt-fájl nem létezik: $prompt_file" >&2
  echo "  (tipp: a kör-brief a KÖR-BRANCHEN van — a munkapéldányban add meg:" >&2
  echo "   $workdir/docs/rounds/<kör>.md)" >&2
  exit 2
fi
if [ ! -d "$workdir/.git" ]; then
  echo "mm-round.sh: a munkapéldány nem git-fa: $workdir" >&2
  exit 2
fi

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# --- Motor-profil a nyilvántartásból (ADR 0140) ---------------------------
# ROUND_ENGINE nélkül a történeti MiniMax-alapértelmezés marad — a régi hívások
# szó szerint ugyanúgy viselkednek.
round_engine=${ROUND_ENGINE:-}
if [ -n "$round_engine" ]; then
  engine_env=$(bash "$script_dir/engine-profile.sh" env "$round_engine" 2>/dev/null) || {
    echo "mm-round.sh: ismeretlen motor: $round_engine" >&2
    exit 2
  }
  while IFS='=' read -r key value; do
    [ -n "$key" ] && export "$key=$value"
  done <<< "$engine_env"
  case "$(grep -m1 "^${round_engine}	" "$script_dir/../docs/execution/engine-registry.tsv" | cut -f2)" in
    claude) ;;
    *) echo "mm-round.sh: a(z) $round_engine motor nem claude-harness — használd a codex-round.sh-t" >&2; exit 2 ;;
  esac
fi

stall_minutes=${MM_STALL_MINUTES:-${ENGINE_STALL_MINUTES:-5}}
round_timeout=${MM_ROUND_TIMEOUT:-${ENGINE_ROUND_TIMEOUT:-3600}}
config_dir=${MM_CONFIG_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude-minimax}}
model=${MM_MODEL:-${ENGINE_MODEL:-MiniMax-M3[1m]}}
# Gondolkodási szint (a nyilvántartás `reasoning` oszlopa): a Claude CLI-nél
# `--effort`, a `-` érték = ne adjunk át semmit.
effort=${ENGINE_REASONING:-"-"}
signal="$workdir/.codex-round-status"
pid_file="$workdir/.mm-round-pid"

# A kulcs sosem kerül fájlba a repóban: vagy a környezetből jön, vagy az
# `mmx` CLI saját configjából olvassuk ki futásidőben.
api_key=${MINIMAX_API_KEY:-}
if [ -z "$api_key" ] && [ -f "$HOME/.mmx/config.json" ]; then
  api_key=$(python3 -c "import json;print(json.load(open('$HOME/.mmx/config.json'))['api_key'])")
fi
# Az ÜZEMMÓDOT a modell dönti el, NEM az ambiens kulcs megléte. (Mérve
# 2026-08-06: a boxon mindig van `~/.mmx/config.json`, ezért a kulcs-alapú
# döntés a natív Claude-modellt is a MiniMax endpointra küldte volna.)
case "$model" in
  claude-*|sonnet-*|opus-*|haiku-*) external_endpoint=0 ;;
  *) external_endpoint=1 ;;
esac
if [ "$external_endpoint" = "1" ] && [ -z "$api_key" ]; then
  echo "mm-round.sh: nincs MiniMax API kulcs (MINIMAX_API_KEY vagy ~/.mmx/config.json)" >&2
  exit 2
fi

rm -f "$signal" "$pid_file"
: > "$log_file"

# Self-heal E06-R07/H7 (docs/LESSONS.md L221) — lásd a codex-round.sh azonos
# szakaszának indoklását: ha a munkapéldány origin-je a hub lokális útvonalára
# mutat, itt (az implementer indulása ELŐTT) a hub saját upstream-jére áll.
bash "$script_dir/fix-workspace-origin.sh" "$workdir" >&2 || true

# Self-heal E08-R03/H6 (docs/LESSONS.md L339) — lásd a codex-round.sh azonos
# szakaszának indoklását: a gitignore-olt generált Flutter/l10n előfeltétel
# munkapéldányonkénti, a `$workdir` SAJÁT másolatát hívjuk argumentum
# nélkül (L232/E06-R13), fail-open.
bash "$workdir/tools/prepare-flutter-generated.sh" >&2 || true

# A scope-audit (ADR 0138) bázisa: a munkapéldány HEAD-je az indítás
# pillanatában — lásd a codex-round.sh azonos szakaszának indoklását.
scope_base=$(git -C "$workdir" rev-parse HEAD 2>/dev/null)

# A `claude -p`-nek nincs `-C` kapcsolója (mint a `codex exec`-nek), ezért a
# munkapéldányba alhéjjal lépünk be — így a kör-jelzés `git rev-parse` hívása
# is a helyes fát látja.
# --- Implementer-őrök (ADR 0309) -----------------------------------------
# A kör-szerződést (allowed_paths, tiltott parancsalakok, lezáró jelzés) gépi
# hook méri, nem prompt-szöveg — a szöveges tiltás mérve nem tartott
# (E02-R07 gate-csonkítás háromszor; két kör listán kívüli fájlt hozott létre;
# H-NOSIGNAL 18 önjavító kör). A hookok CSAK ebben a sessionben élnek: a
# `--settings` a kör munkapéldányából töltődik, és a `STRUMSIGHT_ROUND_BRIEF`
# kapcsolja be őket. Régi ágon (ahol a fájl még nincs meg) a viselkedés
# változatlan — visszafelé kompatibilis.
guard_settings="$workdir/tools/implementer-settings.json"
guard_hook="$workdir/tools/hooks/implementer_guard.py"
round_brief=${ROUND_BRIEF:-}
if [ -z "$round_brief" ]; then
  case "$prompt_file" in
    "$workdir"/docs/rounds/*.md) round_brief=${prompt_file#"$workdir"/} ;;
  esac
fi
# A kör UTÁNI scope-audit (ADR 0138) eddig NÉMÁN kimaradt, ha a hívó nem
# állította be a ROUND_BRIEF-et (mérve: `scope_audit=skipped`,
# `scope_audit_reason=ROUND_BRIEF nincs beállítva`). Most, hogy a briefet
# gépileg levezetjük, az auditált réteg is megkapja — a hook a gyors, lokális
# őr, ez pedig a kör utáni, jelzésfájlba írt bizonyíték.
if [ -z "${ROUND_BRIEF:-}" ] && [ -n "$round_brief" ]; then
  export ROUND_BRIEF="$round_brief"
fi

round_id=${ROUND_ID:-}
if [ -z "$round_id" ] && [ -n "$round_brief" ]; then
  round_id=$(basename "$round_brief" | grep -oE '^[eE][0-9]{2}-[rR][0-9]{2}' | tr '[:lower:]' '[:upper:]')
fi

# A nyilvántartás `max_out` oszlopa eddig HOLT konfiguráció volt a
# claude-harness úton: az `engine-profile.sh` exportálta (`ENGINE_MAX_OUTPUT`),
# de senki nem adta át. A hosszú, több fájlt érintő szerkesztés így a CLI
# alapértelmezésébe futott. A claude-harness megfelelője ez a változó.
launch_env=(CLAUDE_CONFIG_DIR="$config_dir")
[ -n "${ENGINE_MAX_OUTPUT:-}" ] && launch_env+=(CLAUDE_CODE_MAX_OUTPUT_TOKENS="$ENGINE_MAX_OUTPUT")
if [ -n "$round_brief" ] && [ -f "$workdir/$round_brief" ] && [ -f "$guard_settings" ] && [ -f "$guard_hook" ]; then
  launch_env+=(STRUMSIGHT_ROUND_BRIEF="$round_brief" STRUMSIGHT_ROUND_ID="${round_id:-ismeretlen}")
  guard_enabled=1
else
  guard_enabled=0
fi
launch_args=(--model "$model" --permission-mode acceptEdits --strict-mcp-config
  --output-format stream-json --verbose)
[ "$guard_enabled" = "1" ] && launch_args+=(--settings "$guard_settings")
# Kör-auditor alügynök (ADR 0309 §4): a KÖTELEZŐ önellenőrzés ne a modell
# ötletén múljon, hanem kapjon kész, célzott definíciót. A `Task` eszköz a
# claude-harness motoroknál engedélyezett, és mérve működik a MiniMax
# endpointon is.
guard_agents="$workdir/tools/implementer-agents.json"
[ -f "$guard_agents" ] && launch_args+=(--agents "$(cat "$guard_agents")")

if [ "$external_endpoint" = "1" ]; then
  # --- MiniMax M3 sajátosságai (VÁLTOZATLANUL, user-kérés 2026-08-06) -------
  # A `/v1/models` nem ad `context_window`-t, ezért a Claude Code a beépített
  # 200K-s alapértelmezésre esne vissza és ~167K-nál idő előtt compact-olna.
  launch_env+=(
    ANTHROPIC_BASE_URL="https://api.minimax.io/anthropic"
    ANTHROPIC_AUTH_TOKEN="$api_key"
    CLAUDE_CODE_AUTO_COMPACT_WINDOW=1000000
  )
  # A TodoWrite a befejezetlen fa ellen: a listát vezető modell nem felejti
  # el a hátralévő acceptance-pontokat (a félkész fa a lánc legdrágább
  # hibaosztálya).
  #
  # `Task` (alügynökök) — user-döntés 2026-08-18. MÉRVE ezen a boxon, három
  # élő próbával a MiniMax endpointon (nem feltételezés):
  #   1. `Explore` alügynök lefut és helyes eredményt ad;
  #   2. a projekt OPUS-ra rögzített ügynöke (`flutter-reviewer`,
  #      `model: claude-opus-4-8`) is lefut — a `~/.claude-minimax/settings.json`
  #      `ANTHROPIC_DEFAULT_OPUS_MODEL=MiniMax-M3[1m]` leképezése fedi, tehát
  #      NINCS Claude-kvóta-szivárgás (a base URL a MiniMax endpoint);
  #   3. az alügynök `Bash`-t is tud futtatni `--permission-mode acceptEdits`
  #      mellett (`git diff --stat` → BASH_OK).
  # Miért éri meg: a MiniMax mért gyengéi (invariáns-lazítás, fixture-default
  # vakfolt, a handoffba írt nem futtatott állítás — docs/LESSONS.md) mind
  # ÖNELLENŐRZÉSSEL foghatók, és az alügynök friss kontextusból nézi a diffet.
  # A használat szabályait a motor-preambulum §8 köti meg (szinkron futás,
  # nincs `model` felülírás, a gate a szülőben marad).
  launch_args+=(--allowedTools "Read,Write,Edit,Glob,Grep,Bash,TodoWrite,Task")
else
  # --- Natív Claude-modell (Sonnet 5) sajátosságai -------------------------
  # 1. NINCS auto-compact override: a natív modellnél a CLI ISMERI a valódi
  #    ablakot, egy hamis 1M-s érték csak késleltetné a compact-ot a valódi
  #    limiten túlra (a MiniMax-nál pont fordítva igaz).
  # 2. `TodoWrite` a tool-listán: a kör több fájlt érint, és a mért implementer
  #    hibaminta a „félbehagyott, félkész fa" (ADR 0173) — a listát vezető
  #    modell nem felejti el a hátralévő fájlokat.
  # 3. `--effort` a nyilvántartás `reasoning` oszlopából.
  launch_args+=(--allowedTools "Read,Write,Edit,Glob,Grep,Bash,TodoWrite")
fi
[ "$effort" != "-" ] && [ -n "$effort" ] && launch_args+=(--effort "$effort")

# Az implementer-preambulum (ADR 0173) a claude-harness motorra is érvényes: a
# mért hibaminták tiltása artefaktum, nem körönként újraírt prompt-szöveg.
# Motor-specifikus kiegészítés: ha van `implementer-preamble-<motor>.md`, az a
# közös preambulum UTÁN jön — így a motor egyedi erősségeit/gyengeségeit
# külön lehet kezelni anélkül, hogy a közös szöveg hígulna.
preamble_file="$script_dir/../docs/execution/implementer-preamble.md"
engine_preamble="$script_dir/../docs/execution/implementer-preamble-${round_engine:-minimax}.md"
prompt_text=$(cat "$prompt_file")
if [ "${CODEX_NO_PREAMBLE:-0}" != "1" ]; then
  [ -f "$engine_preamble" ] && prompt_text=$(printf '%s\n\n---\n\n%s' "$(cat "$engine_preamble")" "$prompt_text")
  [ -f "$preamble_file" ] && prompt_text=$(printf '%s\n\n---\n\n%s' "$(cat "$preamble_file")" "$prompt_text")
fi

(
  cd "$workdir" || exit 2
  env "${launch_env[@]}" "${CLAUDE_BIN:-claude}" -p "$prompt_text" "${launch_args[@]}"
) >> "$log_file" 2>&1 &
mm_pid=$!
echo "$mm_pid" > "$pid_file"

started=$(date +%s)
killed_reason=""
terminal_signal_seen=""

has_terminal_signal() { grep -qE '^status=(done|stopped|blocked)$' "$signal" 2>/dev/null; }

poll_seconds=${MM_POLL_SECONDS:-20}
# A SIGTERM és a SIGKILL közti türelmi idő. ÉLESBEN változatlanul 5 másodperc —
# egy valódi `claude -p` folyamatnak kell ennyi, hogy a saját takarítását
# befejezze. A burkolót MÉRŐ tesztek viszont hamis, azonnal kilépő binárissal
# dolgoznak, ezért ott ez az 5 mp tiszta, gépfüggetlen fali óra: 20 cellán
# ~100 másodperc a `router-ci` 10 perces job-plafonjából (E14-R13/H5 önjavító
# kör, ADR 0112, 2026-09-05 — `.pipeline/halt-detail-E14-R13.md`). A kapcsoló
# ugyanaz a minta, mint a fenti `MM_POLL_SECONDS`: az ALAPÉRTELMEZÉS az éles
# viselkedés, a teszt csak felgyorsítja azt, amit nem ő mér.
kill_grace_seconds=${MM_KILL_GRACE_SECONDS:-5}
# MÉRT hibaminta (E06-R23 self-heal, ADR 0112, 2026-08-12): a Claude a saját
# STOP-protokollja szerint helyesen megírta a jelzésfájlt
# (`tools/codex-signal.sh stopped ...`, H3 scope-sértés, 22:17:39Z), de a
# `claude -p` folyamat ETTŐL FÜGGETLENÜL futott tovább — MÉG HAT commitot
# hozott létre a jelzés UTÁN, a teljes kör hátralévő részét lezárva, mielőtt
# ~15 perccel később magától kilépett. A jelzésfájl írása eddig csak azt
# garantálta, hogy az orchestrátor `wait-for-round.sh`-ja észreveszi a
# terminális állapotot — magát a folyamatot semmi nem állította le, ezért az
# a pipeline már HALT-olt lánc-állapota mellett, felügyelet nélkül dolgozott
# tovább. A ciklus ezért a `killed_reason`-nel egyenrangúan figyeli a
# jelzésfájlt is; a `terminal_signal_seen` KÜLÖN jelző, hogy a lentebbi „a
# jelzést felülírjuk" ág (csak elakadásnál/időtúllépésnél helyes) ne törölje
# a Claude SAJÁT, helyes jelentését.
while kill -0 "$mm_pid" 2>/dev/null; do
  sleep "$poll_seconds"
  now=$(date +%s)
  log_age=$(( now - $(stat -c %Y "$log_file") ))

  if [ $(( now - started )) -ge "$round_timeout" ]; then
    killed_reason="timeout"
  elif [ "$log_age" -ge $(( stall_minutes * 60 )) ]; then
    killed_reason="stalled"
  elif has_terminal_signal; then
    terminal_signal_seen=1
  fi

  if [ -n "$killed_reason" ] || [ -n "$terminal_signal_seen" ]; then
    kill "$mm_pid" 2>/dev/null || true
    sleep "$kill_grace_seconds"
    kill -9 "$mm_pid" 2>/dev/null || true
    break
  fi
done

wait "$mm_pid" 2>/dev/null
exit_code=$?
rm -f "$pid_file"

# A stream-json log utolsó `result` eseményéből kiemeljük az olvasható
# kör-jelentést, hogy az orchestrátornak ne kelljen JSONL-t olvasnia.
report_file="${log_file%.log}.report.md"
python3 - "$log_file" "$report_file" <<'PY' 2>/dev/null || true
import json, sys
log, out = sys.argv[1], sys.argv[2]
text = ""
for line in open(log, errors="replace"):
    line = line.strip()
    if not line.startswith("{"):
        continue
    try:
        event = json.loads(line)
    except ValueError:
        continue
    if event.get("type") == "result" and event.get("result"):
        text = event["result"]
if text:
    open(out, "w").write(text)
PY

if [ -n "$killed_reason" ]; then
  {
    echo "status=$killed_reason"
    if [ "$killed_reason" = "stalled" ]; then
      echo "summary=a log ${stall_minutes} percig nem nőtt — a futást kilőttük"
    else
      echo "summary=elérte a ${round_timeout}s abszolút időkorlátot — a futást kilőttük"
    fi
    echo "engine=minimax-m3"
    echo "branch=$(git -C "$workdir" branch --show-current)"
    echo "head=$(git -C "$workdir" rev-parse --short HEAD)"
    echo "dirty_files=$(git -C "$workdir" status --porcelain | wc -l | tr -d ' ')"
    echo "signalled_at=$(date -Iseconds)"
  } > "$signal"
  exit_code=1
elif [ ! -f "$signal" ] || ! grep -qE '^status=(done|stopped|blocked)$' "$signal"; then
  {
    echo "status=unknown"
    echo "summary=a MiniMax implementer lezáró jelzés nélkül lépett ki (exit ${exit_code}) — nézd meg: ${log_file}"
    echo "engine=minimax-m3"
    echo "branch=$(git -C "$workdir" branch --show-current)"
    echo "head=$(git -C "$workdir" rev-parse --short HEAD)"
    echo "dirty_files=$(git -C "$workdir" status --porcelain | wc -l | tr -d ' ')"
    echo "signalled_at=$(date -Iseconds)"
  } > "$signal"
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
  # A burkoló SAJÁT artefaktumai (jelzésfájl, pid-fájl, wait-for-round.sh
  # baseline-marker) nem számítanak munkának — nélkülük a „piszkos fa" mindig
  # igaz lenne, és az őr sosem sülne el.
  dirty=$(git -C "$workdir" status --porcelain -- . \
    ':(exclude).codex-round-status' ':(exclude).mm-round-pid' \
    ':(exclude).wait-for-round-baseline' ':(exclude).wait-for-router-baseline' \
    | wc -l | tr -d " ")
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

# Scope-audit (ADR 0138) — közös a legacy Codex úttal.
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
bash "$script_dir/round-scope-audit.sh" "$workdir" "$scope_base" "$signal"
scope_exit=$?
[ "$scope_exit" -eq 1 ] && exit_code=1

echo "--- minimax round finished ---"
echo "log:    $log_file"
[ -f "$report_file" ] && echo "report: $report_file"
cat "$signal"
exit "$exit_code"
