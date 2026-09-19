#!/usr/bin/env bash
# Flutter SDK telepítése a Claude Code REMOTE konténerbe (idempotens).
#
# Miért: a konténer efemer és alapból nincs benne Flutter/Dart SDK, ezért
# minden format/analyze/teszt-lelet csak a ~20 perces CI-körből derül ki
# (mért: docs/execution/remote-container-environment.md §1). Ez a script a
# CI-vel AZONOS Flutter-verziót teszi fel (.github/workflows/build-apk.yml
# `flutter-version`), hogy a helyi `dart format` / `flutter analyze` /
# `flutter test` ugyanazt mondja, mint a kapu.
#
# ELŐFELTÉTEL (a felhasználó állítja, a környezet beállításaiban — Claude
# Code on the web → Environment → Network access): a proxy engedje ezeket a
# hostokat, különben a CONNECT 403 „policy denial"-lal bukik (mért 2026-09-06):
#   storage.googleapis.com   (Flutter SDK archívum + Dart SDK)
#   pub.dev, pub.dartlang.org (csomagok — `flutter pub get`)
#   dl.google.com, maven.google.com (Android/Gradle artefaktumok, csak ha
#                             APK-t is építenél a konténerben)
#   services.gradle.org, repo.maven.apache.org (ugyanahhoz)
#   *.blob.core.windows.net  (GitHub Actions naplók teljes letöltése — a
#                             GitHub MCP tool 5000 sornál csonkol)
# A legegyszerűbb: a környezet hálózati módja „Full access" (vagy a fenti
# allowlist), és ez a script a környezet setup-parancsa:
#   bash tools/remote/install-flutter.sh
#
# Használat:
#   bash tools/remote/install-flutter.sh            # telepít (ha még nincs)
#   FLUTTER_INSTALL_DIR=/opt/flutter bash tools/remote/install-flutter.sh
#   bash tools/remote/install-flutter.sh --check    # csak mér, nem telepít
#
# Utána a shellben: export PATH="$FLUTTER_INSTALL_DIR/bin:$PATH" (a script a
# végén kiírja), és a `.mcp.json` dart MCP-szervere is elindul, ha a
# `dart` bináris a megadott helyre kerül (a konfigurált út:
# /home/ubuntu/flutter/bin/dart — a script erre szimlinket is tesz).
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
workflow="$repo_root/.github/workflows/build-apk.yml"
install_dir="${FLUTTER_INSTALL_DIR:-/opt/flutter}"
mcp_dart_path="/home/ubuntu/flutter/bin/dart"
check_only=0
[[ "${1:-}" == "--check" ]] && check_only=1

# 1. A CI-vel azonos verzió — a forrás az igazság, nem egy másolat.
version="$(grep -m1 -E "flutter-version:\s*'[0-9.]+'" "$workflow" | sed -E "s/.*'([0-9.]+)'.*/\1/")"
if [[ -z "$version" ]]; then
  echo "::error::Nem találom a flutter-version pint a(z) $workflow fájlban." >&2
  exit 1
fi
archive="flutter_linux_${version}-stable.tar.xz"
base="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux"

echo "Flutter $version (a build-apk.yml pinje), célkönyvtár: $install_dir"

# 2. Már fent van?
if [[ -x "$install_dir/bin/flutter" ]]; then
  installed="$("$install_dir/bin/flutter" --version --machine 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin).get("frameworkVersion",""))' 2>/dev/null || true)"
  if [[ "$installed" == "$version" ]]; then
    echo "Már telepítve: Flutter $installed — nincs teendő."
    echo "PATH: export PATH=\"$install_dir/bin:\$PATH\""
    exit 0
  fi
  echo "Más verzió van fent ($installed) — a(z) $version kerül a helyére."
fi

# 3. Hálózati előmérés: egyetlen HEAD kérés dönti el, hogy érdemes-e nekifutni.
if ! curl -sS -o /dev/null --max-time 20 "$base/$archive" -I 2>/dev/null; then
  echo "::error::A(z) storage.googleapis.com nem érhető el a proxyn át (policy denial)." >&2
  echo "Engedélyezd a fejlécben felsorolt hostokat a környezet hálózati beállításaiban," >&2
  echo "majd futtasd újra. Részletek: docs/execution/remote-container-environment.md" >&2
  exit 2
fi
echo "Hálózat OK: $base/$archive elérhető."
(( check_only )) && exit 0

# 4. Letöltés + kibontás (a tar.xz ~700 MB; xz szükséges).
command -v xz >/dev/null || { apt-get update -qq && apt-get install -y -qq xz-utils >/dev/null; }
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
echo "Letöltés…"
curl -sS --fail --max-time 1800 -o "$tmp/$archive" "$base/$archive"
echo "Kibontás…"
mkdir -p "$(dirname "$install_dir")"
rm -rf "$install_dir"
tar -xJf "$tmp/$archive" -C "$(dirname "$install_dir")"
if [[ "$(dirname "$install_dir")/flutter" != "$install_dir" ]]; then
  mv "$(dirname "$install_dir")/flutter" "$install_dir"
fi
git config --global --add safe.directory "$install_dir" || true

# 5. A .mcp.json dart-szervere ezt az utat várja — szimlink, hogy elinduljon.
if [[ ! -e "$mcp_dart_path" ]]; then
  mkdir -p "$(dirname "$mcp_dart_path")" && ln -s "$install_dir/bin/dart" "$mcp_dart_path" || true
fi

# 6. Előmelegítés: Dart SDK letöltése + a repó csomagjai.
export PATH="$install_dir/bin:$PATH"
flutter --version
( cd "$repo_root" && flutter pub get )

echo
echo "KÉSZ. Használat ebben a shellben:"
echo "  export PATH=\"$install_dir/bin:\$PATH\""
echo "Kapu (a CLAUDE.md szerint külön hívásokkal, NEM láncolva):"
echo "  dart format --output=none --set-exit-if-changed lib test tool"
echo "  flutter analyze"
echo "  flutter test test/<érintett terület>"
