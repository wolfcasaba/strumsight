#!/usr/bin/env bash
# Kör-indító burkoló a MiniMax M3 implementerhez (AGENTS.md §15.3, ADR 0069).
#
#   tools/mm-round.sh <munkapéldány> <prompt-fájl> [logfájl]
#
# Ugyanaz a szerződés, mint a tools/codex-round.sh-nál — csak a motor más:
# a Claude Code harness fut, de a MiniMax `/anthropic` endpointja mögött,
# IZOLÁLT config dir-rel (CLAUDE_CONFIG_DIR), hogy az orchestrátor Claude saját
# konfigját és auth-ját ne érintse.
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

stall_minutes=${MM_STALL_MINUTES:-5}
round_timeout=${MM_ROUND_TIMEOUT:-3600}
config_dir=${MM_CONFIG_DIR:-$HOME/.claude-minimax}
model=${MM_MODEL:-MiniMax-M3[1m]}
signal="$workdir/.codex-round-status"
pid_file="$workdir/.mm-round-pid"

# A kulcs sosem kerül fájlba a repóban: vagy a környezetből jön, vagy az
# `mmx` CLI saját configjából olvassuk ki futásidőben.
api_key=${MINIMAX_API_KEY:-}
if [ -z "$api_key" ] && [ -f "$HOME/.mmx/config.json" ]; then
  api_key=$(python3 -c "import json;print(json.load(open('$HOME/.mmx/config.json'))['api_key'])")
fi
if [ -z "$api_key" ]; then
  echo "mm-round.sh: nincs MiniMax API kulcs (MINIMAX_API_KEY vagy ~/.mmx/config.json)" >&2
  exit 2
fi

rm -f "$signal" "$pid_file"
: > "$log_file"

# A scope-audit (ADR 0138) bázisa: a munkapéldány HEAD-je az indítás
# pillanatában — lásd a codex-round.sh azonos szakaszának indoklását.
scope_base=$(git -C "$workdir" rev-parse HEAD 2>/dev/null)

# A `claude -p`-nek nincs `-C` kapcsolója (mint a `codex exec`-nek), ezért a
# munkapéldányba alhéjjal lépünk be — így a kör-jelzés `git rev-parse` hívása
# is a helyes fát látja.
(
  cd "$workdir" || exit 2
  CLAUDE_CONFIG_DIR="$config_dir" \
  ANTHROPIC_BASE_URL="https://api.minimax.io/anthropic" \
  ANTHROPIC_AUTH_TOKEN="$api_key" \
  CLAUDE_CODE_AUTO_COMPACT_WINDOW=1000000 \
  claude -p "$(cat "$prompt_file")" \
    --model "$model" \
    --allowedTools "Read,Write,Edit,Glob,Grep,Bash" \
    --permission-mode acceptEdits \
    --strict-mcp-config \
    --output-format stream-json \
    --verbose
) >> "$log_file" 2>&1 &
mm_pid=$!
echo "$mm_pid" > "$pid_file"

started=$(date +%s)
killed_reason=""

while kill -0 "$mm_pid" 2>/dev/null; do
  sleep 20
  now=$(date +%s)
  log_age=$(( now - $(stat -c %Y "$log_file") ))

  if [ $(( now - started )) -ge "$round_timeout" ]; then
    killed_reason="timeout"
  elif [ "$log_age" -ge $(( stall_minutes * 60 )) ]; then
    killed_reason="stalled"
  fi

  if [ -n "$killed_reason" ]; then
    kill "$mm_pid" 2>/dev/null || true
    sleep 5
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
