#!/usr/bin/env bash
# Merge-zár: a záró rituálék sorosítása párhuzamos körök mellett (ADR 0171 §1).
#
#   tools/round-merge-lock.sh <parancs...>
#
# MIÉRT: két kör futhat párhuzamosan, ha a fájlhalmazuk diszjunkt — DE a záró
# rituálék (`HANDOFF.md`, RTM, `docs/LESSONS.md`, a sor-fájl, a git-notes és
# maga a `main`-re történő squash-merge) MINDEN körnél ugyanazokhoz az
# artefaktumokhoz nyúlnak. Ezek nem tehetők diszjunkttá, ezért nem párhuzamot
# kapnak, hanem sorosítást: aki előbb ér ide, előbb végez.
#
# A zár NEM helyettesíti a zöld kaput: a merge-előfeltételek (review, exact-SHA
# zöld CI, scope-audit) változatlanok. Ez pusztán azt zárja ki, hogy két kör
# EGYSZERRE írja ugyanazt a dokumentumot vagy egyszerre rebase-eljen.
#
# Kilépési kód: a futtatott parancsé; 4 = a zárat a várakozási korláton belül
# nem sikerült megszerezni.
set -uo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
state_dir=${PIPELINE_STATE_DIR:-"$repo_root/.pipeline"}
lock_file=${ROUND_MERGE_LOCK:-"$state_dir/merge.lock"}
wait_seconds=${ROUND_MERGE_LOCK_WAIT:-3600}

if [ "$#" -eq 0 ]; then
  echo "használat: tools/round-merge-lock.sh <parancs...>" >&2
  exit 2
fi

mkdir -p "$(dirname "$lock_file")" || exit 4
exec 7>"$lock_file" || exit 4
if ! flock -w "$wait_seconds" 7; then
  echo "round-merge-lock: a merge-zár ${wait_seconds}s alatt nem szabadult fel ($lock_file)" >&2
  exit 4
fi

"$@"
