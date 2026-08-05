#!/usr/bin/env bash
# A kör-pipeline állapotának megtekintése és feloldása (ADR 0087).
#
#   tools/pipeline-status.sh              # állapot kiírása
#   tools/pipeline-status.sh --resume     # a HALT azonnali feloldása
#   tools/pipeline-status.sh --halt "ok"  # a lánc kézi megállítása
#   tools/pipeline-status.sh --mark-halt H4 "ok" # router H4 átadás
#   tools/pipeline-status.sh --heal-reset # az önjavító kísérletszámláló nullázása
#
# ADR 0112 óta a `--resume` NEM az egyetlen út: haltból a driver magától indít
# önjavító kört (`PIPELINE_SELFHEAL=0` kapcsolja ki). A `--resume` a gyorsítás
# és a `H-GATEGUARD` feloldásának eszköze — az utóbbi az egyetlen eset, ahol a
# lánc kötelezően emberre vár.
set -uo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
state_dir=${PIPELINE_STATE_DIR:-"$repo_root/.pipeline"}
queue_file=${PIPELINE_QUEUE_FILE:-"$repo_root/docs/execution/pipeline-queue.tsv"}
router_status_file="$state_dir/router-status"
halt_file="$state_dir/HALTED"
heal_count_file="$state_dir/selfheal.count"
claude_block_file="$state_dir/claude-blocked-until"
chain_log="$state_dir/chain.log"

write_router_halt() {
  target=$1
  temporary="$target.tmp.$$"
  {
    echo "round=$PIPELINE_ROUND"
    echo "halt=$halt_code"
    echo "summary=$halt_summary"
    echo "halted_at=$(date -Is)"
  } > "$temporary"
  chmod 600 "$temporary"
  mv -f "$temporary" "$target"
}

case "${1:-}" in
  --resume)
    if [ ! -f "$halt_file" ]; then
      echo "A lánc nem áll — nincs mit feloldani."
      exit 0
    fi
    echo "--- a feloldandó HALT ---"
    cat "$halt_file"
    echo "-------------------------"
    archive="$state_dir/halted-$(date +%Y%m%dT%H%M%S).txt"
    mv "$halt_file" "$archive"
    rm -f "$heal_count_file"
    printf '%s  HALT feloldva emberi döntéssel (archívum: %s)\n' \
      "$(date -Is)" "$archive" | tee -a "$chain_log"
    echo "A lánc feloldva. A következő cron-firing viszi a soron következő kört."
    ;;
  --heal-reset)
    rm -f "$heal_count_file"
    printf '%s  önjavító kísérletszámláló nullázva\n' "$(date -Is)" | tee -a "$chain_log"
    ;;
  --unblock-claude)
    rm -f "$claude_block_file"
    printf '%s  Claude-kvótazárlat feloldva — a következő kört újra a Claude viszi\n' \
      "$(date -Is)" | tee -a "$chain_log"
    ;;
  --halt)
    reason=${2:?használat: pipeline-status.sh --halt "<ok>"}
    mkdir -p "$state_dir"
    {
      echo "round=<kézi>"
      echo "halt=H-MANUAL"
      echo "summary=$reason"
      echo "halted_at=$(date -Is)"
    } > "$halt_file"
    echo "A lánc megállítva: $reason"
    ;;
  --mark-halt)
    halt_code=${2:?használat: pipeline-status.sh --mark-halt H4 "<ok>"}
    halt_summary=${3:?használat: pipeline-status.sh --mark-halt H4 "<ok>"}
    case "$halt_code" in H[1-8]) ;; *) echo "érvénytelen halt-kód: $halt_code" >&2; exit 2 ;; esac
    case "${PIPELINE_ROUND:-}" in
      E[0-9][0-9]-R[0-9][0-9]) ;;
      *) echo "PIPELINE_ROUND=E##-R## kötelező a router halt átadásához" >&2; exit 2 ;;
    esac
    halt_summary=$(printf '%s' "$halt_summary" | python3 -c '
import re, sys
value = sys.stdin.read()
value = re.sub(r"(?i)(Authorization\s*:\s*Bearer\s+)\S+", r"\1[REDACTED]", value)
value = re.sub(r"(?i)\b(MINIMAX_API_KEY|OPENAI_API_KEY|CODEX_API_KEY|API_KEY|TOKEN)\s*=\s*\S+", r"\1=[REDACTED]", value)
value = re.sub(r"\bsk-[A-Za-z0-9_-]{20,}\b", "[REDACTED]", value)
print(" ".join(value.split())[:500])
')
    [ -n "$halt_summary" ] || halt_summary="[REDACTED]"
    mkdir -p "$state_dir"
    write_router_halt "$state_dir/router-halt"
    write_router_halt "$halt_file"
    round_status="$state_dir/round-status"
    temporary="$round_status.tmp.$$"
    {
      echo "outcome=halted"
      echo "round=$PIPELINE_ROUND"
      echo "halt=$halt_code"
      echo "summary=$halt_summary"
    } > "$temporary"
    chmod 600 "$temporary"
    mv -f "$temporary" "$round_status"
    printf '%s  router halt átvéve (%s)\n' "$(date -Is)" "$halt_summary" >> "$chain_log"
    echo "Router halt átadva: $halt_code — $halt_summary"
    ;;
  ""|--status)
    echo "=== Kör-pipeline állapot (ADR 0087) ==="
    if [ -f "$halt_file" ]; then
      echo
      echo "!!! A LÁNC ÁLL !!!"
      cat "$halt_file"
      echo
      if grep -q '^halt=H-GATEGUARD' "$halt_file"; then
        echo "MÉRCE-ŐRSZEM (ADR 0112 §3): az önjavítás a gate-hez nyúlt — ezt EMBER dönti el."
      else
        echo "Az önjavító kör (ADR 0112) a következő cron-firingen indul."
      fi
      echo "Azonnali feloldás: tools/pipeline-status.sh --resume"
    elif [ -f "$state_dir/lock" ] && ! flock -n "$state_dir/lock" true 2>/dev/null; then
      echo "Állapot: FUT egy kör (a zár foglalt)."
    else
      echo "Állapot: tétlen, a következő firing indíthat kört."
    fi
    echo
    echo "--- review-motor (ADR 0115) ---"
    if [ "${PIPELINE_FALLBACK_ENGINE:-terra}" = "none" ]; then
      echo "  Claude (fallback KIKAPCSOLVA)"
    elif [ -f "$claude_block_file" ] \
      && [ "$(date +%s)" -lt "$(cat "$claude_block_file" 2>/dev/null || echo 0)" ]; then
      printf '  Terra (gpt-5.6-terra) — a Claude-kvóta zárlat alatt %s-ig\n' \
        "$(date -Is -d "@$(cat "$claude_block_file")" 2>/dev/null)"
      echo "  visszaállítás: tools/pipeline-status.sh --unblock-claude"
    else
      echo "  Claude (elsődleges) · kvótakimerülésnél automatikusan Terra veszi át"
    fi
    echo
    echo "--- önjavítás (ADR 0112) ---"
    if [ "${PIPELINE_SELFHEAL:-1}" != "1" ]; then
      echo "  KIKAPCSOLVA (PIPELINE_SELFHEAL=0)"
    elif [ -f "$heal_count_file" ]; then
      IFS='|' read -r heal_round heal_code heal_n < "$heal_count_file"
      printf '  %s / %s — %s. kísérlet (max %s)\n' \
        "$heal_round" "$heal_code" "$heal_n" "${PIPELINE_SELFHEAL_MAX:-3}"
    else
      echo "  nincs folyamatban lévő önjavítás"
    fi
    echo
    echo "--- áteresztő-képesség (ADR 0171) ---"
    slots_wanted=${PIPELINE_SLOTS:-1}
    slots_effective=$(bash "$repo_root/tools/round-pipeline.sh" --effective-slots "$slots_wanted" 2>/dev/null | tail -1)
    if [ "${PIPELINE_SELF_CHAIN:-1}" = "1" ]; then chain_state="BE"; else chain_state="KI"; fi
    printf '  slot: %s kért → %s tényleges · azonnali lánc-folytatás: %s\n' \
      "$slots_wanted" "${slots_effective:-1}" "$chain_state"
    if [ -d "$state_dir/inflight" ] \
      && [ -n "$(ls "$state_dir/inflight" 2>/dev/null | grep -E '^[A-Z][0-9]{2}-R[0-9]{2}$' || true)" ]; then
      printf '  futó körök: %s\n' \
        "$(ls "$state_dir/inflight" | grep -E '^[A-Z][0-9]{2}-R[0-9]{2}$' | tr '\n' ' ')"
    else
      echo "  futó körök: (egy sincs bejegyezve)"
    fi
    if [ -f "$chain_log" ] && [ -f "$repo_root/tools/round-metrics.py" ]; then
      metrics_line=$(python3 "$repo_root/tools/round-metrics.py" \
        --chain-log "$chain_log" --format summary-line 2>/dev/null)
      [ -n "$metrics_line" ] && printf '  %s\n' "$metrics_line"
    fi
    echo
    echo "--- utolsó router-állapot ---"
    if [ -f "$router_status_file" ]; then
      while IFS= read -r line; do
        case "$line" in
          status=* | router_status=* | summary=* | branch=* | head=* | dirty_files=* | signalled_at=*)
            printf '  %s\n' "$line"
            ;;
        esac
      done < "$router_status_file"
    else
      echo "  (még nincs router-jelzés)"
    fi
    echo
    echo "--- sor ---"
    if [ -f "$queue_file" ]; then
      grep -v '^[[:space:]]*#' "$queue_file" | awk -F'\t' 'NF>=5 {printf "  %-9s %-8s %-6s %s\n", $1, $5, $3, $2}'
    else
      echo "  (nincs sor-fájl)"
    fi
    echo
    echo "--- utolsó 15 lánc-esemény ---"
    [ -f "$chain_log" ] && tail -15 "$chain_log" || echo "  (még nincs)"
    ;;
  *)
    echo "használat: pipeline-status.sh [--status | --resume | --halt \"<ok>\" | --mark-halt H4 \"<ok>\" | --heal-reset | --unblock-claude]" >&2
    exit 2
    ;;
esac
