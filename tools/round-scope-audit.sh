#!/usr/bin/env bash
# Legacy-út scope-audit hook (ADR 0138).
#
#   tools/round-scope-audit.sh <munkapéldány> <base-sha> <signal-fájl>
#
# A `tools/codex-round.sh` és a `tools/mm-round.sh` hívja, MIUTÁN az implementer
# kilépett. Az auditot a `tools/scope-audit.py` végzi a brief `allowed_paths`
# blokkja és a `.ai/router.toml` `protected_paths` listája ellen; ez a burkoló
# csak a jelzésfájlba vezeti át a gépi verdiktet, hogy az orchestrátor NE a log
# olvasásából tudja meg, ha a diff kilógott a körből.
#
# MIÉRT: az `engine=auto` úton a router minden modell-diffet auditál
# (tools/ai_router/security.py), a legacy úton viszont eddig CSAK a prompt
# szövege és a későbbi review védett. A prompt szövege nem kényszerítő erő —
# mérve: az M3 a tiltás ellenére commitolt (git-guard fejléc, docs/LESSONS.md).
#
# Kimenet a jelzésfájlban:
#   scope_audit=ok | VIOLATION | skipped | error
#   scope_audit_violations=<egy sorban, ha VIOLATION>
#
# Sértés esetén a jelzés `status`-a `stopped`-ra vált (az eredeti a
# `implementer_status=` kulcsban marad meg) — ugyanaz az elv, mint az
# időtúllépésnél: a burkoló ténye erősebb, mint az implementer önbevallása.
#
# Kikapcsolás: ROUND_SCOPE_AUDIT=off (csak kézi reprodukcióhoz).
# A brief útvonala a ROUND_BRIEF környezeti változóból jön; ha nincs megadva,
# az audit `skipped` — láthatóan, nem némán.
set -uo pipefail

workdir=${1:?használat: round-scope-audit.sh <munkapéldány> <base-sha> <signal-fájl>}
base=${2:-}
signal=${3:?használat: round-scope-audit.sh <munkapéldány> <base-sha> <signal-fájl>}

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

append_kv() {   # a jelzésfájl KEY=VALUE sorainak bővítése, atomikusan
  local temporary="$signal.tmp.$$"
  { [ -f "$signal" ] && cat "$signal"; printf '%s\n' "$@"; } > "$temporary"
  chmod 600 "$temporary"
  mv -f "$temporary" "$signal"
}

if [ "${ROUND_SCOPE_AUDIT:-on}" = "off" ]; then
  append_kv "scope_audit=skipped" "scope_audit_reason=ROUND_SCOPE_AUDIT=off"
  exit 0
fi

if [ -z "${ROUND_BRIEF:-}" ]; then
  append_kv "scope_audit=skipped" "scope_audit_reason=ROUND_BRIEF nincs beállítva"
  echo "round-scope-audit: ROUND_BRIEF nincs beállítva — az audit KIMARADT" >&2
  exit 0
fi

if [ -z "$base" ]; then
  append_kv "scope_audit=error" "scope_audit_reason=hiányzó base commit"
  echo "round-scope-audit: nincs base commit — az audit nem futtatható" >&2
  exit 2
fi

audit_output=$(
  python3 "$script_dir/scope-audit.py" \
    --repo "$workdir" --brief "$ROUND_BRIEF" --base "$base" --kv 2>&1
)
audit_exit=$?

echo "$audit_output"

# A KEY=VALUE sorokat a python írja; a szöveges riportot nem visszük a
# jelzésfájlba, hogy az KEY=VALUE maradjon.
kv_lines=$(printf '%s\n' "$audit_output" | grep -E '^scope_audit(_[a-z]+)?=' || true)

case "$audit_exit" in
  0)
    [ -n "$kv_lines" ] && append_kv "$kv_lines"
    ;;
  1)
    implementer_status=$(grep -m1 '^status=' "$signal" 2>/dev/null | cut -d= -f2-)
    violations=$(printf '%s\n' "$kv_lines" | grep -m1 '^scope_audit_violations=' | cut -d= -f2-)
    # A `status` sort cseréljük, a többi kulcsot érintetlenül hagyjuk.
    temporary="$signal.tmp.$$"
    {
      grep -v -E '^(status|summary)=' "$signal" 2>/dev/null
      echo "status=stopped"
      echo "summary=scope-sértés: a diff kilógott a brief engedélyezett fájljaiból"
      echo "implementer_status=${implementer_status:-unknown}"
      printf '%s\n' "$kv_lines"
    } > "$temporary"
    chmod 600 "$temporary"
    mv -f "$temporary" "$signal"
    echo "round-scope-audit: SCOPE-SÉRTÉS — ${violations}" >&2
    ;;
  *)
    append_kv "scope_audit=error" "scope_audit_reason=az audit nem futott le (exit $audit_exit)"
    echo "round-scope-audit: az audit nem futott le (exit $audit_exit)" >&2
    ;;
esac

exit "$audit_exit"
