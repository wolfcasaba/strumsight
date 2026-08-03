#!/usr/bin/env bash
# Restores ignored Flutter-generated prerequisites after a checkout or merge.
#
# This is preparation only: it never formats, fixes, or otherwise mutates
# tracked source. The round gate remains the sole quality measurement.
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

if [ ! -f pubspec.yaml ]; then
  exit 0
fi

flutter_bin=${FLUTTER_BIN:-"$HOME/flutter/bin/flutter"}
"$flutter_bin" pub get

if [ -f l10n.yaml ]; then
  "$flutter_bin" gen-l10n
fi
