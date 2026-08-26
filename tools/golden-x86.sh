#!/usr/bin/env bash
# Golden-raszterizáció mérése a MERGE-KAPU architektúráján (ADR 0426).
#
#   tools/golden-x86.sh check  [teszt-útvonal ...]   # csak ellenőriz (alap)
#   tools/golden-x86.sh record [teszt-útvonal ...]   # x86-on VESZ FEL goldent
#
# Útvonal nélkül a `test/` teljes golden-sávja fut (a `matchesGoldenFile`-t
# hívó teszt-fájlok).
#
# MIÉRT: a goldeneket ezen a boxon (aarch64) vesszük fel, a zöld kaput adó CI
# viszont `ubuntu-latest` = x86_64, és a `LocalFileComparator` nulla
# toleranciájú. Ami a két ISA raszterizációja között eltér, az a lokális
# gate-ben MINDIG zöld és a CI-ban MINDIG piros — E13-R17 és E13-R20 együtt
# öt vak CI-kört fizetett ki ezért (docs/LESSONS.md L486, L493). Az L486 saját
# szavaival: „a hordozhatóság ELVBŐL nem mérhető ezen a boxon". Ez a script
# pontosan ezt az ELVI korlátot szünteti meg: a golden-tesztet a CI-vel azonos
# Flutter-verzióval, x86_64 futtatókörnyezetben (qemu-user emuláció) futtatja.
#
# A MÉRCE VÁLTOZATLAN: a komparátor ugyanaz a nulla toleranciájú
# `LocalFileComparator`, a golden-készlet ugyanaz, egyetlen cella sincs
# kihagyva. Csak a mérés HELYE kerül a felvétel mellé.
#
# Kilépési kódok:
#   0  = a goldenek az x86 raszterizációval egyeznek (record: felvéve)
#   10 = golden-eltérés (a `check` sáv valódi piros)
#   20 = környezeti hiba (nincs docker / nincs amd64 emuláció / build bukott)
#   30 = hibás hívás
set -uo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
image_repo=${GOLDEN_X86_IMAGE:-strumsight-golden-x86}
pub_volume=${GOLDEN_X86_PUB_VOLUME:-strumsight-golden-x86-pub}
# A `.dart_tool` NEVESÍTETT köteten él, mert benne van a Dart inkrementális
# kernel-gyorsítótára. Emuláció alatt a fordítás a futás drága fele; kötet
# nélkül minden hívás nulláról fordítana. A gyorsítótár tartalom-hashelt,
# tehát nem tud elavulni a fa alá.
dart_tool_volume=${GOLDEN_X86_DART_TOOL_VOLUME:-strumsight-golden-x86-darttool}

mode=${1:-check}
case "$mode" in
  check|record) shift ;;
  -h|--help)
    sed -n '2,12p' "${BASH_SOURCE[0]}"
    exit 0
    ;;
  *)
    echo "golden-x86.sh: ismeretlen mód: $mode (check|record)" >&2
    exit 30
    ;;
esac

# --- A CI-vel közös Flutter-verzió -----------------------------------------
# EGYETLEN forrás: a workflow-k `flutter-version:` pinje. Ha a workflow-k
# egymásnak ellentmondanak, itt állunk meg — egy szétcsúszott pin pont azt a
# hamis biztonságot adná vissza, amit ez a script megszüntet.
resolve_flutter_version() {
  local versions
  versions=$(grep -rhoE "flutter-version:[[:space:]]*'[^']+'" \
      "$repo_root/.github/workflows/" 2>/dev/null \
    | sed -E "s/.*'([^']+)'.*/\1/" | sort -u)
  if [ -z "$versions" ]; then
    echo "golden-x86.sh: nem található flutter-version pin a .github/workflows/-ban" >&2
    return 1
  fi
  if [ "$(printf '%s\n' "$versions" | wc -l)" -ne 1 ]; then
    echo "golden-x86.sh: a workflow-k Flutter-pinjei eltérnek:" >&2
    printf '  %s\n' $versions >&2
    return 1
  fi
  printf '%s\n' "$versions"
}

flutter_version=$(resolve_flutter_version) || exit 20
image="$image_repo:$flutter_version"

command -v docker >/dev/null 2>&1 || {
  echo "golden-x86.sh: docker nem elérhető" >&2
  exit 20
}

# --- amd64 emuláció ---------------------------------------------------------
if ! docker run --rm --platform linux/amd64 "$image" true >/dev/null 2>&1; then
  if ! grep -qs 'qemu-x86_64' /proc/sys/fs/binfmt_misc/status 2>/dev/null \
     && [ ! -e /proc/sys/fs/binfmt_misc/qemu-x86_64 ]; then
    echo "golden-x86.sh: nincs amd64 binfmt kezelő. Telepítés:" >&2
    echo "  docker run --privileged --rm tonistiigi/binfmt --install amd64" >&2
    # Az emulátor hiánya környezeti hiba, de a kép hiánya nem — a build alább jön.
    if [ "$(uname -m)" != "x86_64" ]; then
      exit 20
    fi
  fi
fi

if ! docker image inspect "$image" >/dev/null 2>&1; then
  echo "golden-x86.sh: x86 Flutter kép építése ($image) — első futáskor hosszú" >&2
  docker build --platform linux/amd64 \
    --build-arg "FLUTTER_VERSION=$flutter_version" \
    -f "$repo_root/tools/docker/golden-x86.Dockerfile" \
    -t "$image" "$repo_root/tools/docker" >&2 || exit 20
fi

# --- Teszt-útvonalak --------------------------------------------------------
if [ "$#" -gt 0 ]; then
  paths=("$@")
else
  mapfile -t paths < <(
    grep -rl 'matchesGoldenFile' "$repo_root/test" --include='*.dart' \
      | sed "s#^$repo_root/##" | sort
  )
fi
if [ "${#paths[@]}" -eq 0 ]; then
  echo "golden-x86.sh: nincs futtatandó golden-teszt" >&2
  exit 30
fi

# --- Izolált munkapéldány ---------------------------------------------------
# A konténer x86 `.dart_tool`-t és x86 pub-artefaktumokat írna; ha a repóban
# tenné, elrontaná a box ARM Flutter-állapotát. Ezért a fa MÁSOLATBAN fut, és
# csak a golden PNG-k (record) illetve a failures/ könyvtárak (check) jönnek
# vissza.
work=$(mktemp -d -t golden-x86-XXXXXX) || exit 20
# A konténer `root`-ként ír néhány generált fát (`ios/Flutter/ephemeral/…`),
# amit a gazda-felhasználó nem tud törölni — MÉRVE az első éles futáson. A
# takarítás ezért hibánál ugyanabban a képben, root-ként fut le.
cleanup() {
  rm -rf "$work" 2>/dev/null && return 0
  docker run --rm --platform linux/amd64 \
    -v "$(dirname "$work")":/hostwork "$image" \
    rm -rf "/hostwork/$(basename "$work")" >/dev/null 2>&1
}
trap cleanup EXIT

tar -C "$repo_root" \
  --exclude=./.git --exclude=./build --exclude=./.dart_tool \
  --exclude=./coverage --exclude=./ml/corpus \
  -cf - . 2>/dev/null | tar -C "$work" -xf - || exit 20

test_cmd=(flutter test)
[ "$mode" = "record" ] && test_cmd+=(--update-goldens)

echo "golden-x86.sh: $mode — Flutter $flutter_version / linux/amd64, ${#paths[@]} teszt-útvonal" >&2

docker run --rm --platform linux/amd64 \
  -v "$work:/repo" -v "$pub_volume:/pub-cache" \
  -v "$dart_tool_volume:/repo/.dart_tool" -w /repo \
  "$image" \
  bash -c 'set -e; flutter pub get >/dev/null; exec "$@"' _ \
  "${test_cmd[@]}" "${paths[@]}"
status=$?

# A felvett/eltért képek visszahozása a repóba, illetve a failures/ könyvtárak
# kimentése — enélkül a mérés nyoma a törölt munkapéldánnyal együtt eltűnne.
if [ "$mode" = "record" ]; then
  (cd "$work" && find test -name '*.png' -path '*goldens*' -print0) \
    | (cd "$work" && tar --null -T - -cf -) \
    | tar -C "$repo_root" -xf - || exit 20
fi
if [ "$status" -ne 0 ] \
  && [ -n "$(cd "$work" && find test -type d -name failures -print -quit)" ]; then
  (cd "$work" && find test -type d -name failures -print0) \
    | (cd "$work" && tar --null -T - -cf -) \
    | tar -C "$repo_root" -xf - || true
  echo "golden-x86.sh: az x86 kimenet a test/**/failures/ könyvtárakban" >&2
fi

if [ "$status" -ne 0 ]; then
  exit 10
fi
exit 0
