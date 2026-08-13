#!/usr/bin/env bash
# Biztonságos rebase-utáni push (ADR 0242 §5.5) — futtatható protokoll, nem
# prompt-szöveg (docs/LESSONS.md L09).
#
# MÉRT ok (2026-08-13, E06-R23 H8): egy konfliktus nélküli rebase utáni
# `git push --force-with-lease` (argumentum nélkül, a lokális remote-tracking
# refre támaszkodva) elutasításra futott, mert a remote közben előrement — a
# javasolt "fetch, majd force-with-lease" feloldás szó szerint végrehajtva
# eldobta volna a remote-on közben landolt commitot. Ez a script azt a négy
# lépést teszi futtatható artefaktummá, amit a halt akkor kézzel, ad-hoc
# derített ki.
#
#   tools/safe-force-push.sh <branch> [<remote>]
#
# Lépések (ADR 0242 §5.5, kötött sorrend):
#   1. a PONTOS remote-ref lefetchelése (nem a lokális tracking-refre
#      hagyatkozunk — az volt a "stale info" hibamód);
#   2. a remote-only commitok felsorolása PATCH-ID alapon
#      (a rebaseelt ekvivalensek NEM remote-only commitok);
#   3. ha van remote-only commit → MEGTAGADVA, a lista kiírásával, push nélkül;
#   4. ha nincs → push a 2. lépésben MÉRT remote SHA-ra vett explicit lease-szel.
#
# Sima `--force` és argumentum nélküli `--force-with-lease` egyaránt TILOS.
#
# Kilépési kódok:
#   0 = push megtörtént
#   2 = hibás hívás, vagy a pontos ref nem fetchelhető
#   3 = MEGTAGADVA — remote-only commit van, push NEM történt
set -euo pipefail

branch=${1:-}
remote=${2:-origin}

if [ -z "$branch" ]; then
  echo "usage: safe-force-push.sh <branch> [<remote>]" >&2
  exit 2
fi

# 1. lépés: a PONTOS ref lefetchelése — a lokális remote-tracking ref lehet
# elavult (ez okozta a mért H8-at), ezért mindig frissen mérünk.
if ! git fetch "$remote" "+refs/heads/$branch:refs/remotes/$remote/$branch" >/dev/null 2>&1; then
  echo "safe-force-push: nem sikerült lefetchelni a(z) $remote/$branch pontos ref-jét" >&2
  exit 2
fi

remote_ref="refs/remotes/$remote/$branch"
remote_sha=$(git rev-parse "$remote_ref")

# 2. lépés: remote-only commitok PATCH-ID alapon. A %m jelöli: "<" = csak a
# bal (remote) oldalon, nincs ekvivalens jobb (HEAD) oldali párja; "=" = van
# ekvivalens párja (rebaseelt duplikátum, NEM remote-only); ">" = csak nálunk.
remote_only=$(git log --cherry-mark --left-right --pretty='format:%m %H %s' \
  "$remote_ref...HEAD" | awk '$1 == "<"')

if [ -n "$remote_only" ]; then
  echo "safe-force-push: MEGTAGADVA — a(z) $remote/$branch-on olyan commit van, ami nálunk nincs (és nincs rebaseelt ekvivalense):" >&2
  printf '%s\n' "$remote_only" | while IFS= read -r line; do
    echo "  ${line#< }" >&2
  done
  echo "safe-force-push: push NEM történt — előbb építsd be ezeket a commitokat (pl. cherry-pick), és futtasd újra" >&2
  exit 3
fi

# 4. lépés: push a 2. lépésben MÉRT SHA-ra vett explicit lease-szel — sosem
# üres/implicit `--force-with-lease`, ami a lokális (esetleg elavult)
# tracking-refre hagyatkozna.
git push --force-with-lease="$branch:$remote_sha" "$remote" "$branch"
