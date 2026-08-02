#!/usr/bin/env bash
# A kör-pipeline állapotának megtekintése és feloldása (ADR 0087).
#
#   tools/pipeline-status.sh              # állapot kiírása
#   tools/pipeline-status.sh --resume     # a HALT azonnali feloldása
#   tools/pipeline-status.sh --halt "ok"  # a lánc kézi megállítása
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
    echo "használat: pipeline-status.sh [--status | --resume | --halt \"<ok>\" | --heal-reset | --unblock-claude]" >&2
    exit 2
    ;;
esac
