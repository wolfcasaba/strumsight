#!/usr/bin/env bash
# Autonóm kör-pipeline driver (ADR 0087).
#
#   tools/round-pipeline.sh [--dry-run]
#
# EGY meghívás = LEGFELJEBB EGY kör, egy FRISS headless orchestrátor-sessionben.
# Cron-ból biztonságosan hívható: ha már fut egy kör, azonnal, sikerrel kilép.
#
# MIÉRT NEM egyetlen hosszú futás láncolja a köröket: az ADR 0052 "egy session
# = egy kör" szabálya a kontextus-szennyezés ellen véd. Egy friss session
# körönként ezt TELJESÍTI, nem kikerüli.
#
# A megállási szerződés (H1–H8) az ADR 0087 §2-ben van; ezt a driver NEM
# értelmezi — az orchestrátor-session dönt, és a `.pipeline/round-status`
# fájlban jelenti. A driver dolga a zár, az előfeltételek, az indítás és a
# lánc-állapot vezetése.
#
# Kilépési kód:
#   0 = a kör lement és merge-elődött, VAGY nem volt teendő (zár/üres sor)
#   3 = HALT (a lánc megállt; `.pipeline/HALTED` tartalmazza az okot)
#   4 = előfeltétel nem teljesült (piszkos fa, nyitott PR, futó workflow)
#   5 = az orchestrátor-session időtúllépéssel vagy jelzés nélkül halt meg
set -uo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root" || exit 4

dry_run=0
[ "${1:-}" = "--dry-run" ] && dry_run=1

state_dir="$repo_root/.pipeline"
queue_file="$repo_root/docs/execution/pipeline-queue.tsv"
prompt_template="$repo_root/docs/execution/pipeline-orchestrator-prompt.md"
lock_file="$state_dir/lock"
halt_file="$state_dir/HALTED"
status_file="$state_dir/round-status"
chain_log="$state_dir/chain.log"

session_timeout=${PIPELINE_SESSION_TIMEOUT:-14400}   # 4 óra: kör + javító kör + CI
claude_bin=${CLAUDE_BIN:-claude}
claude_model=${PIPELINE_MODEL:-opus}

mkdir -p "$state_dir"

log() { printf '%s  %s\n' "$(date -Is)" "$*" | tee -a "$chain_log" >&2; }

# Telefon-értesítés ntfy.sh-n át (user-kérés 2026-07-31). A topic a gitignore-olt
# .pipeline/ntfy-topic fájlban él — a repó publikus, a topic nem kerülhet bele.
# Nincs topic-fájl → néma no-op (az értesítés kényelem, nem kapu).
notify() {
  local title="$1" body="$2" prio="${3:-default}"
  local topic_file="$state_dir/ntfy-topic"
  [ -f "$topic_file" ] || return 0
  curl -s -m 10 -o /dev/null \
    -H "Title: $title" -H "Priority: $prio" -H "Tags: guitar" \
    -d "$body" "https://ntfy.sh/$(cat "$topic_file")" || true
}

die() { log "HIBA: $*"; exit "${2:-4}"; }

# --- 1. Zár ---------------------------------------------------------------
# A `flock -n` NEM blokkol: ha egy másik futás tartja a zárat, ez a firing
# egyszerűen kihagyja magát. Cron-nál pontosan ez a kívánt viselkedés.
exec 9>"$lock_file"
if ! flock -n 9; then
  log "zár foglalt — már fut egy kör, ez a firing kimarad"
  exit 0
fi

# --- 2. Halt-állapot ------------------------------------------------------
if [ -f "$halt_file" ]; then
  log "a lánc MEGÁLLT — $halt_file:"
  cat "$halt_file" >&2
  log "feloldás: tools/pipeline-status.sh --resume"
  exit 3
fi

# --- 3. Előfeltételek -----------------------------------------------------
[ -f "$queue_file" ]      || die "hiányzik a sor-fájl: $queue_file"
[ -f "$prompt_template" ] || die "hiányzik a prompt-sablon: $prompt_template"
command -v "$claude_bin" >/dev/null || die "nincs claude CLI: $claude_bin"
command -v gh >/dev/null            || die "nincs gh CLI"

git fetch -q origin main || die "git fetch origin main sikertelen"

current_branch=$(git rev-parse --abbrev-ref HEAD)
if [ "$current_branch" != "main" ]; then
  die "a munkafa nem a main-en van ($current_branch) — a lánc csak tiszta main-ről indul"
fi
if [ -n "$(git status --porcelain)" ]; then
  die "piszkos munkafa — a lánc nem indul ismeretlen lokális változás fölé"
fi
if [ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]; then
  die "a lokális main eltér az origin/main-től — előbb rendezd (fetch + ff-merge)"
fi

# Párhuzamos autonóm driver ezen a boxon MÉRT jelenség (memória, E02-R01):
# nyitott PR vagy futó workflow = valaki más visz egy kört.
open_prs=$(gh pr list --state open --json number --jq 'length' 2>/dev/null || echo "?")
[ "$open_prs" = "0" ] || die "nyitott PR van ($open_prs) — másik kör lehet folyamatban"

running_runs=$(gh run list --limit 20 --json status \
  --jq '[.[] | select(.status != "completed")] | length' 2>/dev/null || echo "?")
[ "$running_runs" = "0" ] || die "fut egy workflow ($running_runs) — megvárjuk"

# --- 4. A következő kör kiválasztása --------------------------------------
next_line=$(grep -v '^[[:space:]]*#' "$queue_file" | grep -P '\tpending$' | head -1)
if [ -z "$next_line" ]; then
  log "a sorban nincs több 'pending' kör — a lánc végigért"
  exit 0
fi

round=$(printf '%s' "$next_line" | cut -f1)
brief=$(printf '%s' "$next_line" | cut -f2)
engine=$(printf '%s' "$next_line" | cut -f3)
adr=$(printf '%s' "$next_line" | cut -f4)

[ -f "$brief" ] || die "a kör briefje nem létezik: $brief"

log "következő kör: $round · brief=$brief · motor=$engine · ADR=$adr"

if [ "$dry_run" = "1" ]; then
  log "--dry-run: itt indulna az orchestrátor-session, de nem indul"
  exit 0
fi

# --- 5. Az orchestrátor-prompt összeállítása ------------------------------
run_stamp=$(date +%Y%m%dT%H%M%S)
prompt_file="$state_dir/prompt-$round-$run_stamp.md"
session_log="$state_dir/session-$round-$run_stamp.log"

sed -e "s|{{ROUND}}|$round|g" \
    -e "s|{{BRIEF}}|$brief|g" \
    -e "s|{{ENGINE}}|$engine|g" \
    -e "s|{{ADR}}|$adr|g" \
    -e "s|{{STATUS_FILE}}|$status_file|g" \
    -e "s|{{HALT_FILE}}|$halt_file|g" \
    "$prompt_template" > "$prompt_file"

# --- 6. Friss headless orchestrátor-session -------------------------------
rm -f "$status_file"
log "orchestrátor-session indul ($round), időkorlát ${session_timeout}s → $session_log"
notify "▶ $round indul" "motor=$engine · ADR=$adr · friss orchestrátor-session"

# 30 percenkénti életjel, amíg a session fut — a telefonon látszik, hogy dolgozik.
(
  elapsed=0
  while sleep 1800; do
    elapsed=$(( elapsed + 30 ))
    notify "⏳ $round még fut" "${elapsed} perce dolgozik ($engine)" low
  done
) &
pinger_pid=$!

# Az orchestrátor INTERAKTÍV claude sessionként fut egy tmux-ban (user-döntés
# 2026-07-31): az interaktív session automatikusan rákapcsolódik a futó
# remote-control hídra (/rc active), ezért MEGJELENIK a user telefonos
# Code-listájában — a -p és a --bg mód sehol nem látszott. A bootstrap-prompt
# rövid fájl-hivatkozás (az argv-önillesztés — L12 — kizárva); a
# bypass-disclaimer és az MCP-consent egyszer, kézzel elfogadva 2026-07-31-én.
tmux_session="pipeline-$round"
tmux kill-session -t "$tmux_session" 2>/dev/null || true
tmux new-session -d -s "$tmux_session" bash
tmux pipe-pane -t "$tmux_session" -o "cat >> $session_log"
tmux send-keys -t "$tmux_session" "env -u CLAUDE_CONFIG_DIR claude --permission-mode bypassPermissions --model $claude_model 'Pipeline $round — olvasd el es kovesd pontosan a promptot ebbol a fajlbol: $prompt_file'" Enter
log "orchestrátor tmux-session: $tmux_session (látszik a telefon Code-listájában) → $session_log"

# Várakozás a kör-jelzésre; korai kilépés, ha a tmux-session meghalt.
deadline=$(( $(date +%s) + session_timeout ))
session_exit=0
while [ ! -f "$status_file" ]; do
  if [ "$(date +%s)" -ge "$deadline" ]; then
    log "időkorlát lejárt — a tmux-sessiont leállítjuk"
    session_exit=124
    break
  fi
  if ! tmux has-session -t "$tmux_session" 2>/dev/null; then
    # meghalt jelzés nélkül — türelmi kör a fájl-írás versenyére, aztán ki
    sleep 15
    break
  fi
  sleep 30
done
tmux kill-session -t "$tmux_session" 2>/dev/null || true
kill "$pinger_pid" 2>/dev/null


# --- 7. Kimenet osztályozása ----------------------------------------------
# A session KÖTELESSÉGE megírni a $status_file-t. Ha nincs, a jelentését NEM
# fogadjuk el bemondásra — ez ugyanaz a szabály, mint az implementer-oldalon
# (AGENTS.md §15.2): jelzés nélküli futás = bukott futás.
if [ ! -f "$status_file" ]; then
  {
    echo "round=$round"
    echo "halt=H-NOSIGNAL"
    echo "summary=az orchestrátor-session jelzés nélkül ért véget (exit $session_exit)"
    echo "session_log=$session_log"
    echo "halted_at=$(date -Is)"
  } > "$halt_file"
  log "HALT: nincs kör-jelzés — $halt_file"
  notify "⛔ HALT: $round" "az orchestrátor-session jelzés nélkül ért véget — kivizsgálás kell" high
  exit 5
fi

outcome=$(grep -m1 '^outcome=' "$status_file" | cut -d= -f2-)
summary=$(grep -m1 '^summary=' "$status_file" | cut -d= -f2-)

case "$outcome" in
  merged)
    log "$round MERGE-ELVE — $summary"
    notify "✅ $round merge-elve" "$summary"
    git fetch -q origin main && git reset -q --hard origin/main
    # A sor-fájl frissítése SAJÁT commitban, hogy a kör diffjét ne szennyezze.
    sed -i "s|^\($round\t.*\t\)pending$|\1done|" "$queue_file"
    if [ -n "$(git status --porcelain "$queue_file")" ]; then
      git add "$queue_file"
      git commit -q -m "chore(pipeline): $round done (ADR 0087)"
      git push -q origin main || log "FIGYELEM: a sor-fájl push-a nem ment át"
    fi
    log "a lánc mehet tovább; a következő firing viszi a következő kört"
    exit 0
    ;;
  halted)
    halt_code=$(grep -m1 '^halt=' "$status_file" | cut -d= -f2-)
    {
      cat "$status_file"
      echo "session_log=$session_log"
      echo "halted_at=$(date -Is)"
    } > "$halt_file"
    log "HALT ($halt_code) a(z) $round körön — $summary"
    notify "⛔ HALT ($halt_code): $round" "$summary — döntésed kell: pipeline-status.sh --resume" high
    log "feloldás emberi döntés után: tools/pipeline-status.sh --resume"
    exit 3
    ;;
  *)
    {
      echo "round=$round"
      echo "halt=H-BADSIGNAL"
      echo "summary=ismeretlen outcome a kör-jelzésben: '$outcome'"
      echo "session_log=$session_log"
      echo "halted_at=$(date -Is)"
    } > "$halt_file"
    log "HALT: értelmezhetetlen kör-jelzés ('$outcome')"
    notify "⛔ HALT: $round" "értelmezhetetlen kör-jelzés: '$outcome'" high
    exit 5
    ;;
esac
