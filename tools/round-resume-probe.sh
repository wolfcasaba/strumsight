#!/usr/bin/env bash
# Hagyaték-mérés egy újrainduló körhöz (ADR 0112 önjavító kör, 2026-08-24).
#
# MÉRT ok (E09-R26 H-NOSIGNAL). A megölt orchestrátor-session után a kör
# queue-sora `pending` marad, tehát a lánc újra sorra veszi. A
# `docs/execution/pipeline-orchestrator-prompt.md` §0.2 örökség-létrája viszont
# csak KÉT hagyaték-esetet nevezett meg — „kész review NYITOTT leletekkel"
# (→ javító kör) és „commitolt pre-flight" (→ ADR/brief újrahasznosítás) —,
# a kifutása pedig „indíts tisztán". Az E09-R26 állapota (review APPROVED,
# 0 nyitott lelet, 4210 sor implementáció, Full Gate `32758663469` zölden a
# `520be629` head SHA-n, PR nincs) egyik nevesített fokra sem illik: a
# legspecifikusabb fok kifejezetten a NYITOTT leletekhez van kötve. Egy
# újrainduló session emiatt a kifutásra eshet, és tisztán újrakezdhet egy már
# jóváhagyott, zölden mért kört.
#
# A tanulság az E06-R23 self-healből is jön: egy prózai §0.2-utasítás, aminek a
# felderítő parancsa némán 0 találatot ad, nem véd. Ezért itt a hagyaték-állapot
# nem a session belátására van bízva, hanem MÉRVE megy be a promptba
# (ugyanaz az idióma, mint a `{{BRIEF_LINT}}`).
#
# READ-ONLY: a szonda nem módosít semmit, csak mér és jelentést ír a stdoutra.
set -uo pipefail

round=""
repo=""
remote="origin"
out=""
do_fetch=1
workspace_glob="/home/ubuntu/ss-*"

die() { printf 'round-resume-probe: %s\n' "$1" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --round)          round="${2:?}"; shift 2 ;;
    --repo)           repo="${2:?}"; shift 2 ;;
    --remote)         remote="${2:?}"; shift 2 ;;
    --out)            out="${2:?}"; shift 2 ;;
    --workspace-glob) workspace_glob="${2:?}"; shift 2 ;;
    --no-fetch)       do_fetch=0; shift ;;
    *) die "ismeretlen kapcsoló: $1" ;;
  esac
done

[ -n "$round" ] || die "kötelező: --round <EXX-RYY>"
[ -n "$repo" ] || die "kötelező: --repo <útvonal>"
[ -d "$repo/.git" ] || [ -f "$repo/.git" ] || die "nem git munkapéldány: $repo"

slug=$(printf '%s' "$round" | tr 'A-Z' 'a-z')
review_path="docs/reviews/${slug}-review.md"

# A kör-azonosító SAJÁT határa számít: az `e09-r2` NEM prefixelheti az
# `e09-r26`-ot (a §0.2 glob-hibája, E06-R23, fordítottja).
boundary="(^|[^a-z0-9])${slug}([^a-z0-9]|$)"

# A hálózati hívás MINDIG timeout alatt (a H-NOSIGNAL hibaosztály: egy védtelen
# hívás a session belsejében fagy le). A fetch hiánya nem hiba — a
# remote-tracking refekkel dolgozunk tovább.
if [ "$do_fetch" = "1" ]; then
  timeout "${RESUME_PROBE_FETCH_TIMEOUT:-90}" \
    git -C "$repo" fetch --quiet "$remote" >/dev/null 2>&1 || true
fi

# --- 1. A kör ága a remote-on ---------------------------------------------
branch=""
head_sha=""
ahead=""
while IFS= read -r ref; do
  candidate="${ref#refs/remotes/$remote/}"
  [ "$candidate" = "HEAD" ] && continue
  printf '%s' "$candidate" | grep -qE "$boundary" || continue
  branch="$candidate"
  head_sha=$(git -C "$repo" rev-parse "$ref" 2>/dev/null || true)
  ahead=$(git -C "$repo" rev-list --count "$remote/main..$ref" 2>/dev/null || true)
  break
done <<EOF
$(git -C "$repo" for-each-ref --format='%(refname)' "refs/remotes/$remote/" 2>/dev/null)
EOF

# --- 2. A review verdiktje az ágon ----------------------------------------
# Az érvényes verdikt a fájl UTOLSÓ verdikt-sora, és azon belül az UTOLSÓ
# találat — a repó review-korpuszában mért `~~CHANGES REQUIRED~~ → APPROVED`
# javító-köri írásmód miatt. A sorválogatás Unicode-érzékeny (`VÉGSŐ DÖNTÉS`),
# ezért python3 végzi, nem a locale-függő `grep -i`.
verdict="NINCS"
review_seen=0
if [ -n "$branch" ] \
  && git -C "$repo" cat-file -e "$remote/$branch:$review_path" 2>/dev/null; then
  review_seen=1
  verdict=$(git -C "$repo" show "$remote/$branch:$review_path" 2>/dev/null | python3 -c '
import re, sys

text = sys.stdin.read()
KEYWORD = re.compile(r"verdikt|döntés|dontes|decision", re.IGNORECASE)
APPROVED = re.compile(r"APPROVED")
CHANGES = re.compile(r"CHANGES\s+RE(QUIRED|QUESTED)")

verdict = "TISZTÁZATLAN"
for line in text.splitlines():
    if not KEYWORD.search(line):
        continue
    hits = [(m.end(), "APPROVED") for m in APPROVED.finditer(line)]
    hits += [(m.end(), "NYITOTT") for m in CHANGES.finditer(line)]
    if hits:
        verdict = max(hits)[1]
print(verdict)
')
fi

# --- 3. Hagyaték-munkapéldányok -------------------------------------------
workspaces=""
for candidate in $workspace_glob; do
  [ -d "$candidate" ] || continue
  printf '%s' "$(basename "$candidate")" | grep -qE "$boundary" || continue
  workspaces="${workspaces}${workspaces:+$'\n'}$candidate"
done

# --- 4. Besorolás ----------------------------------------------------------
if [ -z "$branch" ] && [ -z "$workspaces" ]; then
  state="NINCS"
elif [ "$review_seen" = "0" ]; then
  state="PRE-FLIGHT"
elif [ "$verdict" = "APPROVED" ]; then
  state="REVIEW-APPROVED"
else
  state="REVIEW-NYITOTT"
fi

# --- 5. A jelentés ---------------------------------------------------------
emit() {
  printf '# %s — hagyaték-mérés (ADR 0112, `tools/round-resume-probe.sh`)\n\n' "$round"
  printf 'ÁLLAPOT: %s\n\n' "$state"

  if [ -n "$branch" ]; then
    printf -- '- Kör-ág a(z) `%s`-on: `%s` @ `%s` (%s commit a `%s/main` felett)\n' \
      "$remote" "$branch" "${head_sha:0:12}" "${ahead:-?}" "$remote"
  else
    printf -- '- Kör-ág a(z) `%s`-on: NINCS\n' "$remote"
  fi

  if [ "$review_seen" = "1" ]; then
    printf -- '- Review: `%s` — az utolsó verdikt: **%s**\n' "$review_path" "$verdict"
  else
    printf -- '- Review: `%s` — nincs az ágon\n' "$review_path"
  fi

  if [ -n "$workspaces" ]; then
    printf -- '- Hagyaték-munkapéldány(ok):\n'
    printf '%s\n' "$workspaces" | while IFS= read -r line; do
      [ -n "$line" ] && printf -- '  - `%s`\n' "$line"
    done
  else
    printf -- '- Hagyaték-munkapéldány: NINCS\n'
  fi

  printf '\n'
  case "$state" in
    NINCS)
      printf '**TEENDŐ:** nincs megőrzendő hagyaték — a kör tisztán indul, a normál pre-flighttal.\n'
      ;;
    PRE-FLIGHT)
      printf '**TEENDŐ:** a commitolt pre-flightot (ADR + §0.0 brief-revízió) OLVASD EL és HASZNÁLD FEL\n'
      printf '(fetch-eld az ágat), ne írd meg vakon újra — két divergens ADR-szöveg ugyanarra a számra\n'
      printf 'rosszabb, mint az újrahasznosítás. Az implementáció innen folytatódik.\n'
      ;;
    REVIEW-NYITOTT)
      printf '**TEENDŐ:** a dolgod NEM a kör újrakezdése, hanem a **következő javító kör** levezénylése:\n'
      printf 'a nyitott leletlistával indítsd az implementert a MEGLÉVŐ ágon, majd frissítsd a review-t,\n'
      printf 'és folytasd a normál lépéssort (§0.3 upstream-szinkron → CI-újradispatch → merge).\n'
      ;;
    REVIEW-APPROVED)
      printf '**TEENDŐ:** ez a kör KÉSZ és JÓVÁHAGYOTT. **Nem** kezded újra, **nem** implementálod újra,\n'
      printf 'és nem indítasz rá implementert. A kör a **merge-lépésnél** folytatódik:\n'
      printf '§0.3 upstream-szinkron (`merge --no-ff %s/main`, normál push) → PR → a teljes CI-kapu\n' "$remote"
      printf 'ÚJRA az így kapott merge SHA-n (Full Gate + Router CI, `tools/wait-for-ci.sh`) →\n'
      printf 'zöld kapus squash-merge. A korábbi zöld futás a RÉGI SHA-n **nem** mentesít.\n'
      printf '\n'
      printf 'Ha a review-t a saját mérésed nyitottnak találja, az felülírja ezt a besorolást —\n'
      printf 'a mérce nem gyengül, csak a fölösleges újrakezdés marad el.\n'
      ;;
  esac
}

if [ -n "$out" ]; then
  emit | tee "$out"
else
  emit
fi
