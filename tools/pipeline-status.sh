#!/usr/bin/env bash
# A kör-pipeline állapotának megtekintése és feloldása (ADR 0087).
#
#   tools/pipeline-status.sh              # állapot kiírása
#   tools/pipeline-status.sh --resume     # a HALT feloldása (EMBERI döntés után)
#   tools/pipeline-status.sh --halt "ok"  # a lánc kézi megállítása
#
# A `--resume` szándékosan NEM automatizálható: az ADR 0087 §2 halt-feltételei
# mind emberi döntést kívánnak. A feloldás azt jelenti: "megnéztem, döntöttem,
# a döntés be van írva a briefbe/ADR-be, mehet tovább".
set -uo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
state_dir="$repo_root/.pipeline"
queue_file="$repo_root/docs/execution/pipeline-queue.tsv"
halt_file="$state_dir/HALTED"
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
    printf '%s  HALT feloldva emberi döntéssel (archívum: %s)\n' \
      "$(date -Is)" "$archive" | tee -a "$chain_log"
    echo "A lánc feloldva. A következő cron-firing viszi a soron következő kört."
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
      echo "Feloldás: tools/pipeline-status.sh --resume"
    elif [ -f "$state_dir/lock" ] && ! flock -n "$state_dir/lock" true 2>/dev/null; then
      echo "Állapot: FUT egy kör (a zár foglalt)."
    else
      echo "Állapot: tétlen, a következő firing indíthat kört."
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
    echo "használat: pipeline-status.sh [--status | --resume | --halt \"<ok>\"]" >&2
    exit 2
    ;;
esac
