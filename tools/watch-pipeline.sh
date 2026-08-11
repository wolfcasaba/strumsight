#!/usr/bin/env bash
# Élő pipeline-figyelő tmux-hoz. Csak OLVAS — semmit nem indít és nem állít le.
cd /home/ubuntu/music-theory || exit 1
while true; do
  clear
  printf '\033[1m  StrumSight — kör-pipeline  \033[0m  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
  printf '  ────────────────────────────────────────────────────────────────\n'

  inflight=$(ls .pipeline/inflight/ 2>/dev/null | grep -E '^[A-Z][0-9]{2}-R[0-9]{2}$' | tr '\n' ' ')
  if [ -n "$inflight" ]; then
    printf '  \033[32m● FUT:\033[0m %s\n' "$inflight"
    for r in $inflight; do
      log=$(ls -t .pipeline/session-$r-*.log 2>/dev/null | head -1)
      [ -n "$log" ] && printf '     log: %s sor · utolsó írás %s\n' \
        "$(wc -l < "$log")" "$(date -d "@$(stat -c %Y "$log")" '+%H:%M:%S')"
    done
  else
    printf '  \033[33m○ nincs futó kör\033[0m\n'
  fi

  printf '\n  \033[1mEpic 6 haladás\033[0m\n'
  done_n=$(grep -cP '^E06.*\tdone$'    docs/execution/pipeline-queue.tsv)
  run_n=$( grep -cP '^E06.*\trunning$' docs/execution/pipeline-queue.tsv)
  pend_n=$(grep -cP '^E06.*\tpending$' docs/execution/pipeline-queue.tsv)
  tot=$((done_n + run_n + pend_n))
  bar=""; i=0
  while [ $i -lt 30 ]; do
    if [ $i -lt "$done_n" ]; then bar="$bar#"; else bar="$bar."; fi
    i=$((i+1))
  done
  printf '  [%s] %s/%s kész · %s fut · %s vár\n' "$bar" "$done_n" "$tot" "$run_n" "$pend_n"

  printf '\n  \033[1mKövetkező sorok\033[0m\n'
  grep -P '^E06.*\t(pending|running)$' docs/execution/pipeline-queue.tsv | head -3 \
    | awk -F'\t' '{printf "    %-9s %-8s %s\n", $1, $5, substr($2,13,52)}'

  printf '\n  \033[1mLánc-napló\033[0m\n'
  tail -6 .pipeline/chain.log 2>/dev/null | sed 's/^/    /' | cut -c1-100

  printf '\n  \033[1mGitHub\033[0m\n'
  gh pr list --limit 2 2>/dev/null | sed 's/^/    /' | cut -c1-96
  gh run list --limit 2 2>/dev/null | awk -F'\t' '{printf "    %-10s %-9s %s\n", $1, $2, substr($3,1,40)}'

  printf '\n  \033[1mGép\033[0m  '
  free -h | awk 'NR==2{printf "RAM %s/%s (avail %s)  ", $3, $2, $7}'
  uptime | grep -o 'load average.*'
  printf '\n  (Ctrl+B majd D = kilépés a nézetből, a lánc fut tovább)\n'
  sleep 20
done
