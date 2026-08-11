#!/usr/bin/env bash
# Egy kör-munkapéldány `origin`-jét a VALÓS upstream-re állítja, ha az egy
# lokális útvonalra mutat (self-heal E06-R07/H7, ADR 0112, docs/LESSONS.md
# L220).
#
#   tools/fix-workspace-origin.sh <munkapéldány>
#
# MIÉRT: a kör-munkapéldányt a codex-round.sh/mm-round.sh elé az orchesztrátor
# `git clone <hub> <cél>`-lal hozza létre (sdd-round-driver SKILL.md §3) — ez
# az `origin`-t a HUB LOKÁLIS ÚTVONALÁRA állítja, nem a GitHub-URL-re. Ha a hub
# (ugyanaz a checkoutolt fő-repó, amelyben az orchesztrátor a pre-flight
# ADR/brief-commitot csinálja) ÉPP a kör branch-én áll — pl. a pre-flight
# commit UTÁN, a `main`-re visszaváltás ELŐTT —, az implementer push-a a hub
# felé `receive.denyCurrentBranch`-sel elutasul: a cél nem-bare repo, és a
# frissítendő ref egyezik a checkoutolt branch-csel.
#
# MÉRVE (E06-R07/H7, 2026-08-11): a munkapéldány commitja (`2e55359c`)
# elkészült, de reviewzhatatlan/merge-elhetetlen maradt, mert a push pontosan
# ezen a mechanizmuson bukott, miközben a hub saját `origin`-je a valódi
# GitHub-URL (a push onnan a GitHub-ra ment volna, ahol nincs checkoutolt
# branch, tehát a denyCurrentBranch fogalma sem értelmezhető).
#
# A javítás STRUKTURÁLIS, nem a hub pillanatnyi állapotát követő: az origin-t
# a hub SAJÁT upstream-jére állítjuk, így egy push egyenesen a GitHub-ra megy —
# a hub nem-bare repo checkoutja irreleváns lesz, bármelyik branch-en is áll.
#
# Fail-open: ez egy védelmi kényelmi lépés, nem egy gate. Ha az origin már
# valódi URL, vagy a hub upstream-je nem határozható meg, a script néma no-op
# (exit 0) — nem hibázik olyan munkapéldányon, ahol nincs mit javítani.
set -uo pipefail

workdir=${1:?használat: fix-workspace-origin.sh <munkapéldány>}

origin_url=$(git -C "$workdir" remote get-url origin 2>/dev/null) || {
  exit 0 # nincs origin remote — nincs mit javítani
}

# Egy már valódi URL (https://, http://, ssh://, git@host:path scp-alak,
# file://) bizonyítottan NEM ez a hiba — hozzá nem érünk.
case "$origin_url" in
  *://*|*@*:*) exit 0 ;;
esac

# Relatív útvonal a hub saját könyvtárához képest értelmezhető (git ezt is
# elfogadja remote-url-ként) — abszolutizáljuk, mielőtt könyvtárként teszteljük.
case "$origin_url" in
  /*) hub_path=$origin_url ;;
  *) hub_path=$workdir/$origin_url ;;
esac

if [ ! -d "$hub_path" ]; then
  exit 0 # nem lokális könyvtár alakú origin — ismeretlen forma, nem nyúlunk hozzá
fi

upstream_url=$(git -C "$hub_path" remote get-url origin 2>/dev/null) || exit 0

case "$upstream_url" in
  *://*|*@*:*) ;;
  *) exit 0 ;; # a hub upstream-je sem valódi URL — az eredeti marad
esac

git -C "$workdir" remote set-url origin "$upstream_url"
echo "fix-workspace-origin.sh: origin lokális útvonalról ($origin_url) a hub valódi upstream-jére állítva: $upstream_url" >&2
