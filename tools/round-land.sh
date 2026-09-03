#!/usr/bin/env bash
# Soros, fail-closed kör-landolás (ADR 0313).
#
#   tools/round-land.sh --pr <szám> --round <E99-R20> [--gate-test <útvonal>]…
#
# A külső hívás mindig a merge-zárat szerzi meg; a belső futás fetch → rebase
# → kombinált-HEAD gate → safe force push → squash merge sorrendű.
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd "$script_dir/.." && pwd)

usage() {
  echo "usage: tools/round-land.sh --pr <number> --round <E99-R20> [--gate-test <relative-test-path>]..." >&2
  exit 2
}

pr=""
round=""
locked=0
declare -a gate_tests=()
declare -a resolved_conflicts=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --_locked)
      locked=1
      shift
      ;;
    --pr)
      [ "$#" -ge 2 ] || usage
      pr=$2
      shift 2
      ;;
    --round)
      [ "$#" -ge 2 ] || usage
      round=$2
      shift 2
      ;;
    --gate-test)
      [ "$#" -ge 2 ] || usage
      gate_tests+=("$2")
      shift 2
      ;;
    *)
      usage
      ;;
  esac
done

[[ "$pr" =~ ^[1-9][0-9]*$ ]] || usage
[[ "$round" =~ ^[A-Za-z][A-Za-z0-9]*-[A-Za-z][A-Za-z0-9]*$ ]] || usage
for gate_test in "${gate_tests[@]}"; do
  case "$gate_test" in
    "" | -* | /* | ../* | *"/../"* | */..)
      usage
      ;;
  esac
done

if [ "$locked" -eq 0 ]; then
  locked_arguments=(--_locked --pr "$pr" --round "$round")
  for gate_test in "${gate_tests[@]}"; do
    locked_arguments+=(--gate-test "$gate_test")
  done
  exec "$script_dir/round-merge-lock.sh" "$script_dir/round-land.sh" "${locked_arguments[@]}"
fi

pipeline_dir=${PIPELINE_STATE_DIR:-"$repo_root/.pipeline"}
log_file="$pipeline_dir/land-$round.log"
mkdir -p "$pipeline_dir"
exec >"$log_file" 2>&1

signal() {
  "$script_dir/codex-signal.sh" "$1" "$2"
}

blocked() {
  local message=$1
  echo "round-land: BLOCKED — $message" >&2
  signal blocked "$message"
  exit 1
}

round_lower=${round,,}
shopt -s nullglob
brief_candidates=("$repo_root/docs/rounds/$round_lower"-*.md)
shopt -u nullglob
if [ "${#brief_candidates[@]}" -ne 1 ]; then
  blocked "a saját brief nem azonosítható egyértelműen: $round"
fi
own_brief=${brief_candidates[0]#"$repo_root"/}

branch=$(git -C "$repo_root" branch --show-current)
if [ -z "$branch" ]; then
  blocked "detached HEAD-ről nem landolható kör"
fi
starting_head=$(git -C "$repo_root" rev-parse HEAD)

cd "$repo_root"
pr_metadata=""
if ! pr_metadata=$(gh pr view "$pr" --json baseRefName,headRefName,headRefOid \
  --jq '[.baseRefName, .headRefName, .headRefOid] | @tsv'); then
  blocked "a PR strukturált metaadata nem kérdezhető le; push és merge nem történt"
fi
pr_base=""
pr_head_branch=""
pr_head_oid=""
pr_metadata_extra=""
if ! IFS=$'\t' read -r pr_base pr_head_branch pr_head_oid pr_metadata_extra <<< "$pr_metadata"; then
  blocked "a PR strukturált metaadata olvashatatlan; push és merge nem történt"
fi
if [ -z "$pr_base" ] || [ -z "$pr_head_branch" ] || [ -z "$pr_head_oid" ] || [ -n "$pr_metadata_extra" ] \
  || [ "$pr_base" != "main" ] || [ "$pr_head_branch" != "$branch" ] || [ "$pr_head_oid" != "$starting_head" ]; then
  blocked "a PR metaadata nem egyezik a mért local HEAD-del; push és merge nem történt"
fi

echo "round-land: round=$round pr=$pr branch=$branch head=$starting_head"
git fetch origin main

self_duplicate_guard() {
  # H8-SELFDUP (E99-R20 self-heal): egy korábbi rebase már lefutott ezen a
  # branch-en (landed_head != starting_head → blocked, exact-SHA CI kérve
  # lásd D1 6. lépés), és a válasz tévedésből a régi, rebase ELŐTTI csúcsot
  # MERGE-elte vissza a friss csúcsba (a rebase.sh-ban ehhez semmilyen
  # kódút nem vezet — külső beavatkozás). Az eredmény: a branch saját
  # tartalma kétszer szerepel benne, ami a valódi rebase-t self-inflicted
  # add/add és content konfliktusokba futtatja (ezek NEM origin/main-nel
  # való valódi ütközések). Ezt itt, a rebase megkísérlése ELŐTT kapjuk el,
  # egyértelmű diagnózissal a megtévesztő, sokfájlos H8 helyett.
  local base pairs duplicate_ids offenders
  base=$(git merge-base HEAD origin/main)
  pairs=$(git log --no-merges --format='commit %H' -p "$base..HEAD" | git patch-id --stable)
  [ -n "$pairs" ] || return 0
  duplicate_ids=$(printf '%s\n' "$pairs" | awk '{print $1}' | sort | uniq -d)
  [ -n "$duplicate_ids" ] || return 0
  offenders=$(awk 'NR==FNR {dup[$1]=1; next} ($1 in dup) {print $2}' \
    <(printf '%s\n' "$duplicate_ids") <(printf '%s\n' "$pairs") | tr '\n' ' ')
  blocked "H8-SELFDUP: a branch saját története ugyanazt a tartalmat kétszer tartalmazza (érintett commitok: ${offenders}). Ez jellemzően egy korábbi 'exact-SHA CI szükséges' blokkolásra adott hibás válasz — a régi, rebase előtti csúcsot MERGE-elték vissza, ahelyett hogy friss CI-t kértek és újrafuttatták volna a landolót. NE ismételd meg ezt: építsd újra a branch-et EGYETLEN tiszta rebase-szel a duplikátumok nélkül, és csak utána fuss neki újra."
}
self_duplicate_guard

resolve_conflicts() {
  local conflicts conflict
  while true; do
    conflicts=$(git diff --name-only --diff-filter=U)
    if [ -z "$conflicts" ]; then
      git rebase --abort || true
      blocked "H8: a rebase konfliktusállapota nem olvasható"
    fi

    while IFS= read -r conflict; do
      case "$conflict" in
        HANDOFF.md | docs/LESSONS.md | docs/ui/migration-status.md | "$own_brief")
          ;;
        *)
          git rebase --abort
          blocked "H8: szemantikus rebase-konfliktus: $conflicts"
          ;;
      esac
    done <<< "$conflicts"

    while IFS= read -r conflict; do
      case "$conflict" in
        HANDOFF.md | docs/LESSONS.md | docs/ui/migration-status.md)
          # Append-only napló: mindkét oldal új része maradjon meg; csak a
          # Git konfliktusjelölőit vesszük ki. A migrációs napló ADR 0495 D2
          # óta tartozik ide: minden kör a SAJÁT dátumozott blokkját fűzi
          # hozzá, és egyetlen gépi mérce sem olvassa a tartalmát a fa ellen.
          awk '!/^(<<<<<<<|=======|>>>>>>>)/' "$conflict" > "$conflict.round-land" \
            && mv "$conflict.round-land" "$conflict"
          git add "$conflict"
          resolved_conflicts+=("$conflict")
          ;;
        "$own_brief")
          # Rebase alatt az "ours" az upstream origin/main, ez a friss brief.
          git checkout --ours -- "$conflict"
          git add "$conflict"
          resolved_conflicts+=("$conflict")
          ;;
      esac
    done <<< "$conflicts"

    if GIT_EDITOR=true git rebase --continue; then
      return 0
    fi
    if [ -n "$(git diff --name-only --diff-filter=U)" ]; then
      continue
    fi
    git rebase --abort || true
    blocked "H8: a mechanikus konfliktus feloldása után a rebase nem folytatható"
  done
}

if git merge-base --is-ancestor origin/main HEAD; then
  echo "round-land: a branch már tartalmazza a friss origin/main-et; rebase kihagyva"
else
  if ! git rebase origin/main; then
    resolve_conflicts
  fi
fi

if [ "${#gate_tests[@]}" -eq 0 ]; then
  gate_tests=("test/tooling/architecture_allowlist_guard_test.dart")
fi
if ! "$script_dir/round-gate.sh" "${gate_tests[@]}"; then
  blocked "a kombinált HEAD gate-je piros; napló: $log_file"
fi

if "$script_dir/safe-force-push.sh" "$branch"; then
  :
else
  push_code=$?
  if [ "$push_code" -eq 3 ]; then
    blocked "a safe-force-push remote-only commitot talált; push és merge nem történt"
  fi
  blocked "a safe-force-push hibával állt le ($push_code); push és merge nem történt"
fi

landed_head=$(git rev-parse HEAD)
if [ "$landed_head" != "$starting_head" ]; then
  rebase_resolved_summary="nincs"
  if [ "${#resolved_conflicts[@]}" -gt 0 ]; then
    rebase_resolved_summary=$(IFS=', '; echo "${resolved_conflicts[*]}")
  fi
  blocked "a rebase új HEAD-et képzett ($landed_head); exact-SHA CI-dispatch szükséges a merge előtt; mechanikusan feloldva: $rebase_resolved_summary"
fi

if ! gh pr merge "$pr" --squash --delete-branch; then
  blocked "a GitHub squash-merge nem sikerült"
fi

resolved_summary="nincs"
if [ "${#resolved_conflicts[@]}" -gt 0 ]; then
  resolved_summary=$(IFS=', '; echo "${resolved_conflicts[*]}")
fi
signal done "sikeres landolás; mechanikusan feloldva: $resolved_summary"
echo "round-land: sikeres squash-merge előkészítés"
