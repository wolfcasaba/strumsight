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
# ÖNJAVÍTÁS (ADR 0112, user-döntés 2026-08-01: "az orchestrátor MINDIG javítsa
# a hibát, a cél az autonóm fejlesztés"): a HALT már nem a lánc vége, hanem egy
# JAVÍTÓ KÖR bemenete. Halt esetén a driver friss önjavító sessiont indít, amely
# megjavítja az akadályt (akár az infrastruktúrában), a változatlan zöld kapun
# átviszi, merge-eli, és feloldja a láncot. Korlátok: körönként és halt-kódonként
# legfeljebb PIPELINE_SELFHEAL_MAX kísérlet, és a MÉRCE gyengítése (kevesebb
# teszt-fájl, módosított round-gate.sh / CI-workflow) automatikusan emberhez
# eszkalál — a mércét nem javíthatja az, akit mér (docs/LESSONS.md).
#
# Kilépési kód:
#   0 = a kör lement és merge-elődött, VAGY nem volt teendő (zár/üres sor),
#       VAGY az önjavítás sikerült és a lánc feloldva
#   3 = HALT, amit az önjavítás sem oldott fel (`.pipeline/HALTED` = az ok)
#   4 = előfeltétel nem teljesült (piszkos fa, nyitott PR, futó workflow)
#   5 = az orchestrátor-session időtúllépéssel vagy jelzés nélkül halt meg
set -uo pipefail

validate_engine() {
  case "${1:-}" in
    auto | minimax | codex) return 0 ;;
    *) return 1 ;;
  esac
}

if [ "${1:-}" = "--validate-engine" ]; then
  [ "$#" -eq 2 ] && validate_engine "$2" || {
    echo "engine must be one of: auto | minimax | codex" >&2
    exit 2
  }
  exit 0
fi

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root" || exit 4

dry_run=0
[ "${1:-}" = "--dry-run" ] && dry_run=1

state_dir=${PIPELINE_STATE_DIR:-"$repo_root/.pipeline"}
queue_file="$repo_root/docs/execution/pipeline-queue.tsv"
prompt_template="$repo_root/docs/execution/pipeline-orchestrator-prompt.md"
heal_template="$repo_root/docs/execution/pipeline-selfheal-prompt.md"
codex_preamble="$repo_root/docs/execution/pipeline-codex-orchestrator-preamble.md"
lock_file="$state_dir/lock"
halt_file="$state_dir/HALTED"
status_file="$state_dir/round-status"
heal_status_file="$state_dir/heal-status"
heal_count_file="$state_dir/selfheal.count"
router_status_file="$state_dir/router-status"
chain_log="$state_dir/chain.log"

session_timeout=${PIPELINE_SESSION_TIMEOUT:-14400}   # 4 óra: kör + javító kör + CI
heal_timeout=${PIPELINE_SELFHEAL_TIMEOUT:-10800}     # 3 óra: diagnózis + fix + CI
selfheal_enabled=${PIPELINE_SELFHEAL:-1}
selfheal_max=${PIPELINE_SELFHEAL_MAX:-3}
claude_bin=${CLAUDE_BIN:-claude}
# Opus 4.8 az orchestrátor-default (user-döntés 2026-08-04: „kapcsoljuk vissza
# a Claude-ot Opus 4.8-cal, továbbá a fejlesztő legyen a Terra"). Az implementer
# ettől a döntéstől Terra (queue engine=codex), a Claude dolga a terv + a review
# + a merge-kapu — oda a nagyobb ítélőképesség kell.
# Korábbi default: claude-sonnet-5 (user-döntés 2026-08-01, kvótaszűke miatt).
claude_model=${PIPELINE_MODEL:-claude-opus-4-8}

# Orchestrátor-fallback (ADR 0115, user-döntés 2026-08-02: „a lényeg, hogy a
# pipeline ne szakadjon meg — a Terra vegye át a review-munkát"). A Terra saját
# CODEX_HOME-ban él, ahol a default model gpt-5.6-terra.
fallback_engine=${PIPELINE_FALLBACK_ENGINE:-terra}   # terra | none
codex_bin=${CODEX_BIN:-codex}
codex_home=${PIPELINE_FALLBACK_CODEX_HOME:-$HOME/.codex-terra}
fallback_label="Terra (gpt-5.6-terra)"
claude_block_file="$state_dir/claude-blocked-until"
claude_block_seconds=${PIPELINE_CLAUDE_BLOCK_SECONDS:-18000}   # 5 órás ablak
claude_stats_cache=${PIPELINE_CLAUDE_STATS_CACHE:-$HOME/.claude/stats-cache.json}

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

# --- Friss headless orchestrátor-session futtatása -------------------------
# Az orchestrátor és az önjavító kör ugyanazt a mechanikát használja: tmux-ban
# futó agent (így látszik a telefonos Code-listában), 30 percenkénti életjel, és
# a session KÖTELESSÉGE egy jelzésfájlt írni. A visszatérési érték 0, ha a
# jelzésfájl megszületett; 1, ha nem (időtúllépés vagy néma halál).
#
# MOTORFÜGGETLEN (ADR 0115): a Claude-kvóta kimerülése nem szakíthatja meg a
# láncot — akkor ugyanezt a promptot a Codex/Terra viszi tovább.

# A Claude-kvóta kimerülésének MÉRT nyomai a session-naplóban. Szándékosan
# angol, CLI-specifikus minták: a magyar „kvóta" szó a promptokban is szerepel,
# arra illeszteni hamis pozitív lenne.
CLAUDE_LIMIT_PATTERN='usage limit reached|Claude usage limit|out of (usage|credits)|insufficient (credit|quota)|rate.?limit(ed)? exceeded|quota exceeded|upgrade to continue|limit will reset'

claude_unavailable_until() {   # kiírja a lejárati epoch-ot, ha érvényes zárlat van
  local until
  [ -f "$claude_block_file" ] || return 1
  until=$(cat "$claude_block_file" 2>/dev/null)
  case "$until" in ''|*[!0-9]*) return 1 ;; esac
  [ "$(date +%s)" -lt "$until" ] || { rm -f "$claude_block_file"; return 1; }
  printf '%s\n' "$until"
}

# A Claude CLI a kvótát indításkor távolról ellenőrzi, de ha a saját friss
# stats-cache-e már a CLI limit-üzenetét tartalmazza, a felesleges tmux-session
# helyett azonnal a fallbackot indítjuk. Cache hiánya vagy ismeretlen tartalma
# nem zárlat: ilyen esetben a session-napló marad a bizonyíték.
claude_stats_cache_unavailable_until() {
  [ -r "$claude_stats_cache" ] || return 1
  grep -qEi "$CLAUDE_LIMIT_PATTERN" "$claude_stats_cache" 2>/dev/null || return 1
  printf '%s\n' "$(( $(date +%s) + claude_block_seconds ))"
}

# A tmux-session felügyelete a jelzésfájlig. Egyetlen paraméterben kapja a
# héj-parancsot, ezért motorfüggetlen.
run_tmux_session() {
  local tmux_session="$1" shell_command="$2" session_log="$3" signal_file="$4"
  local timeout_s="$5" label="$6" watch_claude_limit="${7:-0}"
  local deadline pinger_pid claude_started_at claude_limit_seen=0 pane_tty

  tmux kill-session -t "$tmux_session" 2>/dev/null || true
  tmux new-session -d -s "$tmux_session" bash
  tmux pipe-pane -t "$tmux_session" -o "cat >> $session_log"
  tmux send-keys -t "$tmux_session" "$shell_command" Enter
  log "session indult: $tmux_session (látszik a telefon Code-listájában) → $session_log"

  (
    # fd 9 (a lánc-zár) lezárása az alhéjban — különben a pinger örökli, és a
    # driver halála után árvaként fogva tartaná a zárat (mérve 2026-07-31).
    exec 9>&-
    local elapsed=0
    while sleep 1800; do
      elapsed=$(( elapsed + 30 ))
      notify "⏳ $label még fut" "${elapsed} perce dolgozik" low
    done
  ) &
  pinger_pid=$!

  deadline=$(( $(date +%s) + timeout_s ))
  claude_started_at=$(date +%s)
  while [ ! -f "$signal_file" ]; do
    if [ "$(date +%s)" -ge "$deadline" ]; then
      log "időkorlát lejárt ($label) — a tmux-sessiont leállítjuk"
      break
    fi
    if [ "$watch_claude_limit" = "1" ] \
      && tail -n "${PIPELINE_CLAUDE_LIMIT_LOG_LINES:-80}" "$session_log" 2>/dev/null \
        | grep -qEi "$CLAUDE_LIMIT_PATTERN"; then
      log "KVÓTA: Claude limit-nyom érkezett a futó session-naplóba — a tmux-sessiont azonnal leállítjuk"
      claude_limit_seen=1
      break
    fi
    if ! tmux has-session -t "$tmux_session" 2>/dev/null; then
      # meghalt jelzés nélkül — türelmi kör a fájl-írás versenyére, aztán ki
      sleep 15
      break
    fi
    if [ "$watch_claude_limit" = "1" ] \
      && [ "$(( $(date +%s) - claude_started_at ))" -ge "${PIPELINE_CLAUDE_PROCESS_GRACE_SECONDS:-10}" ]; then
      pane_tty=$(tmux list-panes -t "$tmux_session" -F '#{pane_tty}' 2>/dev/null | head -n 1)
      if [ -n "$pane_tty" ] \
        && ! ps -t "${pane_tty#/dev/pts/}" -o comm= 2>/dev/null | grep -q '[c]laude-code'; then
        printf '%s\n' "$(( $(date +%s) + claude_block_seconds ))" > "$claude_block_file"
        log "KVÓTA: a Claude process már nem él a tmux pane-on — a fallback veszi át"
        claude_limit_seen=1
        break
      fi
    fi
    sleep 30
  done
  tmux kill-session -t "$tmux_session" 2>/dev/null || true
  kill "$pinger_pid" 2>/dev/null

  [ "$claude_limit_seen" = "1" ] && return 0
  [ -f "$signal_file" ]
}

# A Codex/Terra ugyanazt a prompt-fájlt kapja, egy motor-specifikus előszóval
# (nincs skill-rendszere, ezért a skill-fájlt fájlként olvassa el).
codex_prompt_file() {
  local prompt_file="$1" merged="${prompt_file%.md}-codex.md"
  {
    [ -f "$codex_preamble" ] && cat "$codex_preamble"
    printf '\n---\n\n'
    cat "$prompt_file"
  } > "$merged"
  printf '%s\n' "$merged"
}

# Egy orchestrátori munkadarab levezénylése: elsőként Claude, kvótazárlat vagy
# kvótára utaló néma halál esetén Codex/Terra. 0 = van jelzésfájl.
run_orchestrator_session() {
  local tmux_session="$1" prompt_file="$2" session_log="$3" signal_file="$4"
  local timeout_s="$5" label="$6"
  local blocked_until codex_prompt

  rm -f "$signal_file"

  if blocked_until=$(claude_unavailable_until); then
    log "a Claude-kvóta zárlat alatt van $(date -Is -d "@$blocked_until")-ig — a kört a $fallback_label viszi"
  elif blocked_until=$(claude_stats_cache_unavailable_until); then
    printf '%s\n' "$blocked_until" > "$claude_block_file"
    log "a Claude stats-cache aktív kvótazárlatot jelez — a kört a $fallback_label viszi"
  else
    if run_tmux_session "$tmux_session" \
      "env -u CLAUDE_CONFIG_DIR $claude_bin --permission-mode bypassPermissions --model $claude_model 'Pipeline $label — olvasd el es kovesd pontosan a promptot ebbol a fajlbol: $prompt_file'" \
      "$session_log" "$signal_file" "$timeout_s" "$label" 1 \
      && [ -f "$signal_file" ]; then
      return 0
    fi

    if ! grep -qEi "$CLAUDE_LIMIT_PATTERN" "$session_log" 2>/dev/null \
      && ! claude_unavailable_until >/dev/null; then
      return 1   # nem kvóta: valódi hiba, ne égessük rá a Codex-keretet
    fi
    # A zárlat a Claude 5 órás ablakához igazodik; a pontos reset-időt nem
    # parse-oljuk (formátumfüggő lenne), a felső becslés biztonságos: a lánc
    # addig is halad, csak a másik motoron.
    printf '%s\n' "$(( $(date +%s) + claude_block_seconds ))" > "$claude_block_file"
    log "KVÓTA: a Claude-session limitre futott — átadás a $fallback_label motornak"
    notify "🔁 motorváltás: $label" "a Claude-kvóta kimerült — a $fallback_label veszi át" high
  fi

  if [ "$fallback_engine" = "none" ]; then
    log "nincs engedélyezett fallback motor (PIPELINE_FALLBACK_ENGINE=none) — a lánc áll"
    return 1
  fi
  command -v "$codex_bin" >/dev/null || { log "nincs $codex_bin CLI — a fallback nem indítható"; return 1; }

  codex_prompt=$(codex_prompt_file "$prompt_file")
  run_tmux_session "${tmux_session}-fallback" \
    "CODEX_HOME=$codex_home $codex_bin exec -C $repo_root -s danger-full-access \"\$(cat $codex_prompt)\" < /dev/null" \
    "${session_log%.log}-fallback.log" "$signal_file" "$timeout_s" "$label ($fallback_label)" 0
}

# --- Önjavítás (ADR 0112) --------------------------------------------------
# A mérce ujjlenyomata. Az önjavító kör NÖVELHETI a tesztek számát, de nem
# csökkentheti, és a gate-artefaktumokhoz nem nyúlhat. Ha mégis: nem oldjuk fel
# a láncot magunktól — ez az EGYETLEN pont, ahol ember dönt (docs/LESSONS.md,
# „a mércét is ellenőrizd").
gate_test_count() { git -C "$repo_root" ls-files -- test tools/tests | wc -l | tr -d ' '; }
gate_artifact_hashes() {
  local path
  for path in tools/round-gate.sh .github/workflows/build-apk.yml .github/workflows/router-ci.yml; do
    printf '%s:%s ' "$path" "$(git -C "$repo_root" rev-parse "HEAD:$path" 2>/dev/null || echo hiányzik)"
  done
}

# H-GATEGUARD false-positive fix (E03-R05, mért gyökérok): a heal branch neve
# determinisztikus (`heal/{{ROUND}}-{{HALT_CODE}}-{{ATTEMPT}}`, lásd
# docs/execution/pipeline-selfheal-prompt.md), ezért a heal SAJÁT diffje
# közvetlenül lekérdezhető a hozzá tartozó, squash-merge-elt PR-en keresztül —
# ahelyett, hogy a teljes main-t hasonlítanánk össze két időpontban. Az utóbbi
# hamis pozitívat ad, ha a heal FUTÁSA ALATT egy független, jogos commit
# (pl. egy másik ADR bevezetése) landol main-re és éppen egy őrzött útvonalat
# érint — pontosan ez történt: 8715773 (ADR 0115) a heal 07:50–08:08 közötti
# futása KÖZBEN módosította a router-ci.yml-t, a heal saját PR-je (#61) viszont
# egyáltalán nem nyúlt hozzá.
heal_pr_number() {   # $1=heal branch → a hozzá tartozó, MERGE-ELT PR száma (üres, ha nincs)
  gh pr list --search "head:$1" --state merged --json number --jq '.[0].number // empty' 2>/dev/null
}

heal_pr_gate_violation() {   # $1=PR szám → kiírja az okot és 0-val tér vissza, ha a heal SAJÁT diffje gyengítette a mércét; 1, ha nem (vagy nem eldönthető)
  local pr="$1" merge_sha base_sha files deleted
  merge_sha=$(gh pr view "$pr" --json mergeCommit --jq '.mergeCommit.oid // empty' 2>/dev/null)
  [ -n "$merge_sha" ] || return 1
  base_sha="${merge_sha}^"
  git -C "$repo_root" rev-parse "$base_sha" >/dev/null 2>&1 || return 1
  files=$(git -C "$repo_root" diff --name-only "$base_sha" "$merge_sha" -- \
    tools/round-gate.sh .github/workflows/build-apk.yml .github/workflows/router-ci.yml 2>/dev/null)
  if [ -n "$files" ]; then
    printf 'a heal saját PR-je (#%s) gate-artefaktumot módosított: %s' \
      "$pr" "$(printf '%s' "$files" | tr '\n' ',' | sed 's/,$//')"
    return 0
  fi
  deleted=$(git -C "$repo_root" diff --name-status "$base_sha" "$merge_sha" -- test tools/tests 2>/dev/null \
    | grep -c '^D')
  if [ "${deleted:-0}" -gt 0 ]; then
    printf 'a heal saját PR-je (#%s) %s teszt-fájlt törölt' "$pr" "$deleted"
    return 0
  fi
  return 1
}

heal_attempts() {   # $1=kör $2=halt-kód → az eddigi kísérletek száma
  local key="$1|$2" line
  [ -f "$heal_count_file" ] || { echo 0; return; }
  line=$(cat "$heal_count_file")
  case "$line" in
    "$key|"*) printf '%s\n' "${line##*|}" ;;
    *) echo 0 ;;
  esac
}

# --- Terra napi-budget felfüggesztés (E03-R08 H6 önjavítás, 2026-08-02) ----
# MÉRT történeti gyökérok: pozitív Terra napi automatikus budget mellett
# (.ai/router.toml max_automatic_terra_calls_per_utc_day > 0) a keret kizárólag
# UTC nap-váltáskor nyílik meg újra — egy 5 percenkénti cron-retry ugyanazt a
# falat éri újra. A 0 érték 2026-08-02 óta korlátlant jelent; a helper ezért
# a korábbi véges policyből maradt holdot is biztonságosan eltávolítja. A hold
# kör-specifikus és időkorlátos: a
# `terra-status` CLI ugyanazt a `daily_terra_count`-ot kérdezi, amit
# `reserve_terra` is a döntéséhez használ (state.py) — nincs duplikált szabály.
terra_hold_file() { printf '%s/terra-budget-hold' "$state_dir"; }

terra_status_json() {   # stdout: a terra-status JSON, vagy üres, ha nem lekérdezhető
  python3 "$repo_root/tools/model-router.py" --config "$repo_root/.ai/router.toml" terra-status 2>/dev/null
}

terra_daily_budget_is_unlimited() {
  local status_json
  status_json=$(terra_status_json) || return 1
  [ -n "$status_json" ] || return 1
  printf '%s' "$status_json" | python3 -c \
    'import json,sys; raise SystemExit(0 if json.load(sys.stdin).get("unlimited") is True else 1)' \
    2>/dev/null
}

terra_hold_if_exhausted() {   # $1=kör — hold-fájlt ír, ha a napi Terra-budget MOST kimerült
  local round="$1" status_json exhausted next_epoch
  # Módosítás (ADR 0112 önjavító kör, 2026-08-02, E03-R08 H6 2. javítás):
  # `terra-status` a dokumentált viselkedése szerint (HANDOFF.md) NEMNULLA
  # exit-tel tér vissza pontosan akkor, amikor exhausted=true — a korábbi
  # `|| return 0` ezt az esetet is hibaként kezelte, ezért a hold-fájl SOHA
  # nem íródott ki (4 egymást követő H6 halt ugyanazon a napon, mielőtt ezt
  # mérve megtalálták). A tényleges lekérdezési hiba jele az ÜRES kimenet,
  # amit az alábbi sor már önmagában is véd.
  status_json=$(terra_status_json)
  [ -n "$status_json" ] || return 0
  exhausted=$(printf '%s' "$status_json" | python3 -c "import json,sys; print(json.load(sys.stdin).get('exhausted'))" 2>/dev/null)
  [ "$exhausted" = "True" ] || return 0
  next_epoch=$(printf '%s' "$status_json" | python3 -c "import json,sys; print(json.load(sys.stdin).get('next_reset_epoch'))" 2>/dev/null)
  case "$next_epoch" in ''|*[!0-9]*) return 0 ;; esac
  printf 'round=%s\nhold_until=%s\n' "$round" "$next_epoch" > "$(terra_hold_file)"
  log "Terra napi automatikus budget kimerült — $round felfüggesztve $(date -Is -d "@$next_epoch")-ig (a firing-ok addig session és önjavítási kísérlet nélkül kilépnek)"
}

terra_clear_stale_halt_for() {   # $1=kör — ha a HALTED fájl UGYANERRE a körre és Terra napi-budget kimerülésre hivatkozik (H6), ÉS a napi budget MOST már korlátlan, archiválja a HALTED-et, hogy a következő firing a KÖRT próbálja újra, ne egy újabb önjavító sessiont indítson egy már megszűnt okra
  # Módosítás (ADR 0112 önjavító kör, 2026-08-02, E03-R08 H6 7. előfordulás):
  # a hold-fájl törlése (`terra_hold_active_for`) önmagában NEM ELÉG — a
  # HALT-fájlt egy KORÁBBI firing írta ki (`handle_round_halt`, a HALT
  # ELSŐ észlelésekor), és a driver 2. szakasza (`[ -f "$halt_file" ]`)
  # attól teljesen függetlenül dönt, hogy létezik-e még hold-fájl. MÉRT
  # eset (élesben, ebben a repóban): a napi Terra-korlát eltávolítása
  # (PR #72) utáni ELSŐ firing helyesen törölte az akkor még élő
  # `terra-budget-hold` fájlt (a hold-fájl ezután nem is létezik többé) —
  # de a stale HALTED-et (a MÉG korlátozott policy alatt kiírva) ettől
  # függetlenül otthagyta, és a driver egy 7. valódi heal-sessiont
  # indított rá. Ezért ez a függvény ÖNÁLLÓAN, a hold-fájl állapotától
  # FÜGGETLENÜL kérdezi le a policy-t — nem feltételezi, hogy a hívó már
  # megerősítette a korlátlan állapotot.
  local round="$1" stamp halt_round halt_code halt_summary
  [ -f "$halt_file" ] || return 0
  halt_round=$(grep -m1 '^round=' "$halt_file" | cut -d= -f2-)
  [ "$halt_round" = "$round" ] || return 0
  halt_code=$(grep -m1 '^halt=' "$halt_file" | cut -d= -f2-)
  [ "$halt_code" = "H6" ] || return 0
  halt_summary=$(grep -m1 '^summary=' "$halt_file" | cut -d= -f2-)
  case "$halt_summary" in
    *"Terra"*"budget"*) : ;;
    *) return 0 ;;
  esac
  terra_daily_budget_is_unlimited || return 0
  stamp=$(date +%Y%m%dT%H%M%S)
  mv "$halt_file" "$state_dir/healed-$round-$stamp.txt"
  rm -f "$heal_count_file"
  log "a HALTED jelzés elavult volt (a Terra napi-korlát megszűnt, miközben a HALT rá hivatkozott) — törölve, a(z) $round kör önjavítás nélkül újra sorra kerül"
}

terra_hold_active_for() {   # $1=kör → 0 ha AKTÍV hold van rá, 1 egyébként (lejárt/nincs/másik kör → törli a lejárt/idegen fájlt)
  local round="$1" hold_file hold_round hold_until
  hold_file=$(terra_hold_file)
  [ -f "$hold_file" ] || return 1
  hold_round=$(grep -m1 '^round=' "$hold_file" | cut -d= -f2-)
  hold_until=$(grep -m1 '^hold_until=' "$hold_file" | cut -d= -f2-)
  case "$hold_until" in ''|*[!0-9]*) rm -f "$hold_file"; return 1 ;; esac
  if [ "$hold_round" = "$round" ] && [ "$(date +%s)" -lt "$hold_until" ]; then
    if terra_daily_budget_is_unlimited; then
      if ! rm -f "$hold_file"; then
        log "elavult Terra-hold nem törölhető — biztonságosan aktívnak kezeljük"
        return 0
      fi
      log "Terra napi automatikus budget korlátlan — az elavult hold törölve ($round)"
      return 1
    fi
    log "Terra napi budget felfüggesztés aktív ($round, $(date -Is -d "@$hold_until")-ig) — a firing kihagyva, nincs session, nincs önjavítási kísérlet"
    return 0
  fi
  rm -f "$hold_file"
  return 1
}

handle_round_halt() {   # $1=kör $2=status-fájl $3=session-napló — a HALT ELSŐ észlelésekor: halt_file írás + Terra-hold determinisztikus ellenőrzés
  # Módosítás (ADR 0112 önjavító kör, 2026-08-02, E03-R08 H6 5. előfordulás,
  # lásd docs/LESSONS.md L63 folytatása): korábban a Terra napi-hold
  # KIZÁRÓLAG az önjavítás retry-ágából íródott ki (attempt_selfheal, az
  # LLM-jelentés szövegére string-matchelve). Ha egy heal-kör egy MÁSIK
  # gyökérokot javított (pl. magát a hold-író függvényt, PR #70) —
  # `outcome=fixed`, nem `retry` —, ez az ág soha nem futott le, és a
  # következő firing UGYANAZT a naptár-korlátozott Terra-falat érte el
  # újra (4 halt egy napon, 14:26–16:38 UTC). A hívás itt, a HALT ELSŐ
  # észlelésekor — mielőtt bármilyen self-heal session elindulna —
  # determinisztikus: az élő terra-status-t kérdezi le, nem az LLM
  # jelentésének szövegére épül.
  local round="$1" status_file="$2" session_log="$3" halt_code summary
  halt_code=$(grep -m1 '^halt=' "$status_file" | cut -d= -f2-)
  summary=$(grep -m1 '^summary=' "$status_file" | cut -d= -f2-)
  {
    cat "$status_file"
    echo "session_log=$session_log"
    echo "halted_at=$(date -Is)"
  } > "$halt_file"
  terra_hold_if_exhausted "$round"
  log "HALT ($halt_code) a(z) $round körön — $summary"
  notify "⛔ HALT ($halt_code): $round" "$summary — az önjavító kör a következő firingen indul" high
  log "az önjavítás (ADR 0112) a következő cron-firingen indul; kikapcsolva: PIPELINE_SELFHEAL=0"
}

# Kimenet: 0 = a halt feloldva, mehet tovább a lánc; 3 = áll, ember kell.
attempt_selfheal() {
  local halt_round halt_code attempts stamp prompt_file heal_log
  local tests_before hashes_before tests_after hashes_after outcome summary
  local heal_branch pr_number violation

  halt_round=$(grep -m1 '^round=' "$halt_file" | cut -d= -f2-)
  halt_code=$(grep -m1 '^halt=' "$halt_file" | cut -d= -f2-)
  [ -n "$halt_round" ] || halt_round="ismeretlen"
  [ -n "$halt_code" ] || halt_code="H-UNKNOWN"

  if [ "$selfheal_enabled" != "1" ]; then
    log "önjavítás kikapcsolva (PIPELINE_SELFHEAL=0) — a feloldás emberi: tools/pipeline-status.sh --resume"
    return 3
  fi
  if [ ! -f "$heal_template" ]; then
    log "hiányzik az önjavító prompt-sablon ($heal_template) — a lánc áll"
    return 3
  fi

  attempts=$(heal_attempts "$halt_round" "$halt_code")
  if [ "$attempts" -ge "$selfheal_max" ]; then
    log "az önjavítás KIMERÜLT ($attempts/$selfheal_max) — $halt_round / $halt_code"
    notify "🛑 önjavítás kimerült: $halt_round" \
      "$halt_code — $selfheal_max kísérlet után is áll, emberi döntés kell" high
    return 3
  fi
  attempts=$(( attempts + 1 ))
  printf '%s|%s|%s\n' "$halt_round" "$halt_code" "$attempts" > "$heal_count_file"

  # A mérce állapota a javítás ELŐTT, a jelenlegi main-en.
  git fetch -q origin main 2>/dev/null || true
  tests_before=$(gate_test_count)
  hashes_before=$(gate_artifact_hashes)

  stamp=$(date +%Y%m%dT%H%M%S)
  prompt_file="$state_dir/heal-prompt-$halt_round-$stamp.md"
  heal_log="$state_dir/heal-$halt_round-$stamp.log"
  sed -e "s|{{ROUND}}|$halt_round|g" \
      -e "s|{{HALT_CODE}}|$halt_code|g" \
      -e "s|{{ATTEMPT}}|$attempts|g" \
      -e "s|{{MAX_ATTEMPTS}}|$selfheal_max|g" \
      -e "s|{{HALT_FILE}}|$halt_file|g" \
      -e "s|{{HEAL_STATUS_FILE}}|$heal_status_file|g" \
      "$heal_template" > "$prompt_file"

  log "ÖNJAVÍTÓ KÖR indul: $halt_round / $halt_code ($attempts/$selfheal_max)"
  notify "🔧 önjavítás indul: $halt_round" "$halt_code · $attempts/$selfheal_max kísérlet"

  if ! run_orchestrator_session "heal-$halt_round-$attempts" "$prompt_file" "$heal_log" \
        "$heal_status_file" "$heal_timeout" "önjavítás $halt_round"; then
    log "az önjavító session jelzés nélkül ért véget — a lánc áll"
    notify "⛔ önjavítás jelzés nélkül halt" "$halt_round / $halt_code — kivizsgálás kell" high
    return 3
  fi

  outcome=$(grep -m1 '^outcome=' "$heal_status_file" | cut -d= -f2-)
  summary=$(grep -m1 '^summary=' "$heal_status_file" | cut -d= -f2-)

  case "$outcome" in
    fixed)
      : # lentebb: mérce-őrszem, majd feloldás
      ;;
    retry)
      # Külső, átmeneti akadály (kvóta, szolgáltatás-kiesés): nem volt mit
      # javítani a repóban. Feloldjuk a láncot, de a kísérletszámlálót MEGTARTJUK,
      # hogy egy tartós kiesés ne pörgesse a láncot a végtelenségig.
      mv "$halt_file" "$state_dir/healed-$halt_round-$stamp.txt"
      log "átmeneti akadály volt ($summary) — a lánc feloldva, a kör újra sorra kerül"
      notify "🔁 újrapróbálás: $halt_round" "$summary"
      case "$summary" in
        *"Terra daily budget is exhausted"* | *"Terra"*"budget"*)
          terra_hold_if_exhausted "$halt_round"
          ;;
      esac
      return 0
      ;;
    *)
      log "az önjavítás nem oldotta fel ($outcome) — $summary"
      notify "⛔ önjavítás sikertelen: $halt_round" "$outcome — $summary" high
      return 3
      ;;
  esac

  # A javítás után a main-t szinkronizáljuk, és MEGMÉRJÜK a mércét.
  git checkout -q main 2>/dev/null || true
  git fetch -q origin main && git reset -q --hard origin/main
  tests_after=$(gate_test_count)
  hashes_after=$(gate_artifact_hashes)

  # Az őrszem a heal SAJÁT diffjét vizsgálja (determinisztikus branch-név →
  # a hozzá tartozó merge-elt PR), NEM a teljes main előtte/utána állapotát —
  # az utóbbi hamis pozitívat adna egy, a heal futása KÖZBEN landolt, tőle
  # független commitra (mért eset: E03-R05 H6, lásd docs/LESSONS.md).
  heal_branch="heal/${halt_round}-${halt_code}-${attempts}"
  pr_number=$(heal_pr_number "$heal_branch")
  violation=""
  if [ -n "$pr_number" ]; then
    violation=$(heal_pr_gate_violation "$pr_number") || violation=""
  else
    log "GATEGUARD: nincs merge-elt PR a(z) $heal_branch branch-hez — a teljes main-ujjlenyomatra esünk vissza"
    if [ "$tests_after" -lt "$tests_before" ] || [ "$hashes_after" != "$hashes_before" ]; then
      violation="nem található a heal saját PR-je a determinisztikus branch-néven, és a teljes main-ujjlenyomat is változott (teszt-fájlok: $tests_before → $tests_after)"
    fi
  fi

  if [ -n "$violation" ]; then
    {
      echo "round=$halt_round"
      echo "halt=H-GATEGUARD"
      echo "summary=az önjavítás a MÉRCÉHEZ nyúlt — emberi jóváhagyás kell: $violation"
      echo "detail=eredeti halt: $halt_code · javítás: $summary · napló: $heal_log"
      echo "halted_at=$(date -Is)"
    } > "$halt_file"
    log "ŐRSZEM: az önjavítás gyengíthette a mércét — a lánc áll (H-GATEGUARD)"
    notify "⛔ H-GATEGUARD: $halt_round" "az önjavítás a gate-hez nyúlt — nézd át, mielőtt feloldod" high
    return 3
  fi

  mv "$halt_file" "$state_dir/healed-$halt_round-$stamp.txt"
  rm -f "$heal_count_file"
  log "ÖNJAVÍTÁS KÉSZ — a lánc feloldva: $summary"
  notify "✅ önjavítás kész: $halt_round" "$summary — a lánc megy tovább"
  return 0
}

# --- Teszthorgok ----------------------------------------------------------
# A mérce futtatható artefaktum legyen, ne prompt-szöveg (docs/LESSONS.md):
# az önjavítás két gépi döntése kívülről is lekérdezhető, ezért tesztelhető.
case "${1:-}" in
  --heal-attempts)   # $2=kör $3=halt-kód → eddigi kísérletek száma
    heal_attempts "${2:-}" "${3:-}"
    exit 0
    ;;
  --gate-fingerprint)
    printf 'tests=%s %s\n' "$(gate_test_count)" "$(gate_artifact_hashes)"
    exit 0
    ;;
  --heal-pr-number)   # $2=heal branch → a hozzá tartozó merge-elt PR száma (üres, ha nincs)
    heal_pr_number "${2:-}"
    exit 0
    ;;
  --heal-pr-gate-violation)   # $2=PR szám → kiírja az okot, exit 0 ha a heal saját diffje gyengítette a mércét, exit 1 ha nem
    if heal_pr_gate_violation "${2:-}"; then
      exit 0
    else
      exit 1
    fi
    ;;
  --orchestrator-engine)   # melyik motor vinné MOST a review-t (ADR 0115)
    if [ "$fallback_engine" != "none" ] && claude_unavailable_until >/dev/null; then
      printf '%s\n' "$fallback_engine"
    else
      printf 'claude\n'
    fi
    exit 0
    ;;
  --claude-limit-check)    # $2=session-napló → 0, ha kvótakimerülés nyoma van
    grep -qEi "$CLAUDE_LIMIT_PATTERN" "${2:-/dev/null}" 2>/dev/null
    exit $?
    ;;
  --terra-hold-active)    # $2=kör → exit 0 ha AKTÍV Terra napi-budget hold van rá, 1 egyébként
    if terra_hold_active_for "${2:-}"; then
      exit 0
    else
      exit 1
    fi
    ;;
  --terra-hold-if-exhausted)    # $2=kör → teszthorog: meghívja terra_hold_if_exhausted-et (E03-R08 H6 2. javítás)
    terra_hold_if_exhausted "${2:-}"
    exit 0
    ;;
  --handle-round-halt)    # $2=kör $3=status-fájl $4=session-napló → teszthorog: a HALT ELSŐ észlelésének útvonala (E03-R08 H6 5. javítás)
    handle_round_halt "${2:-}" "${3:-}" "${4:-}"
    exit 0
    ;;
  --terra-clear-stale-halt)    # $2=kör → teszthorog: meghívja terra_clear_stale_halt_for-ot (E03-R08 H6 7. javítás)
    terra_clear_stale_halt_for "${2:-}"
    exit 0
    ;;
esac

# --- 1. Zár ---------------------------------------------------------------
# A `flock -n` NEM blokkol: ha egy másik futás tartja a zárat, ez a firing
# egyszerűen kihagyja magát. Cron-nál pontosan ez a kívánt viselkedés.
exec 9>"$lock_file"
if ! flock -n 9; then
  log "zár foglalt — már fut egy kör, ez a firing kimarad"
  exit 0
fi

# --- 1.5 Terra napi-budget felfüggesztés (E03-R08 H6 önjavítás) -----------
# Ha egy pozitív vészlimit mellett egy korábbi retry MÉRVE találta a napi
# Terra-budgetet kimerültnek, a hold-fájl UTC éjfélig felfüggeszti a rá
# vonatkozó firing-okat. Korlátlan policyre váltáskor az elavult hold törlődik.
# A hold
# a HALTOLT kör sorára, vagy — ha épp nincs halt — a sorban következő
# 'pending' körre vonatkozik (ugyanaz a kör, ha a lánc még nem jutott tovább).
active_round=""
if [ -f "$halt_file" ]; then
  active_round=$(grep -m1 '^round=' "$halt_file" | cut -d= -f2-)
elif [ -f "$queue_file" ]; then
  active_round=$(grep -v '^[[:space:]]*#' "$queue_file" | grep -P '\tpending$' | head -1 | cut -f1)
fi
if [ -n "$active_round" ] && terra_hold_active_for "$active_round"; then
  exit 0
fi
[ -n "$active_round" ] && terra_clear_stale_halt_for "$active_round"

# --- 2. Halt-állapot → önjavítás (ADR 0112) -------------------------------
# A halt nem a lánc vége, hanem az önjavító kör bemenete. A driver ugyanezen a
# záron belül indítja: egyszerre továbbra is EGY session dolgozik.
if [ -f "$halt_file" ]; then
  log "a lánc MEGÁLLT — $halt_file:"
  cat "$halt_file" >&2
  if attempt_selfheal; then
    log "az önjavítás feloldotta a láncot; a következő firing viszi a kört"
    exit 0
  fi
  log "a lánc továbbra is áll — feloldás: tools/pipeline-status.sh --resume"
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
validate_engine "$engine" || die "ismeretlen implementer motor: $engine (auto|minimax|codex)"
if [ "$engine" = "auto" ]; then
  [ -x "$repo_root/tools/ai-router-round.sh" ] || die "hiányzik a router adapter"
  [ -x "$repo_root/tools/model-router.py" ] || die "hiányzik a model router"
  [ -f "$repo_root/.ai/router.toml" ] || die "hiányzik a router konfiguráció"
fi

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
    -e "s|{{ROUTER_STATUS_FILE}}|$router_status_file|g" \
    -e "s|{{HALT_FILE}}|$halt_file|g" \
    "$prompt_template" > "$prompt_file"

# --- 6. Friss headless orchestrátor-session -------------------------------
rm -f "$status_file" "$router_status_file"
log "orchestrátor-session indul ($round), időkorlát ${session_timeout}s → $session_log"
notify "▶ $round indul" "motor=$engine · ADR=$adr · friss orchestrátor-session"

# Az orchestrátor INTERAKTÍV claude sessionként fut egy tmux-ban (user-döntés
# 2026-07-31): az interaktív session automatikusan rákapcsolódik a futó
# remote-control hídra (/rc active), ezért MEGJELENIK a user telefonos
# Code-listájában — a -p és a --bg mód sehol nem látszott. A bootstrap-prompt
# rövid fájl-hivatkozás (az argv-önillesztés — L12 — kizárva); a
# bypass-disclaimer és az MCP-consent egyszer, kézzel elfogadva 2026-07-31-én.
session_exit=0
run_orchestrator_session "pipeline-$round" "$prompt_file" "$session_log" \
  "$status_file" "$session_timeout" "$round" || session_exit=124


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
  git checkout -q main 2>/dev/null || true
  log "HALT: nincs kör-jelzés — $halt_file (az önjavítás a következő firingen indul)"
  notify "⛔ HALT: $round" "az orchestrátor-session jelzés nélkül ért véget — önjavítás indul" high
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
    git checkout -q main 2>/dev/null || log "figyelem: a munkafa nem tért vissza mainre"
    handle_round_halt "$round" "$status_file" "$session_log"
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
