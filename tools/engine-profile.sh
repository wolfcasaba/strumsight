#!/usr/bin/env bash
# Implementer-motor profilváltó (ADR 0139).
#
#   tools/engine-profile.sh list            # nyilvántartás + aktív + elérhetőség
#   tools/engine-profile.sh show            # csak az aktív motor neve
#   tools/engine-profile.sh use <name>      # MINDEN kör ezzel a motorral megy
#   tools/engine-profile.sh clear           # vissza a queue soronkénti értékére
#   tools/engine-profile.sh check <name>    # élő füst-teszt (egy olcsó hívás)
#   tools/engine-profile.sh env <name>      # a wrapperhez: KEY=VALUE sorok
#
# MIÉRT KELL: a motorok kvótája külön-külön merül ki (a Terra 9%-on, 2026-08-05),
# és a kifogyott motor helyett azonnal váltani kell — de úgy, hogy a régi
# BÁRMIKOR visszakapcsolható maradjon. A profilok ezért egymás mellett élnek
# (`~/.codex-terra`, `~/.codex-kilo`, `~/.claude-minimax`), és a váltás egyetlen
# fájl írása, nem konfigurációk átírása.
#
# Az override a `.pipeline/engine-override` fájl (gitignore-olt): ha létezik, a
# driver MINDEN körre ezt a motort használja a queue `engine` oszlopa helyett.
# Törlésével a queue soronkénti értéke lép vissza életbe — nincs elveszett
# beállítás, nincs visszaírt konfig.
set -uo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
registry="$repo_root/docs/execution/engine-registry.tsv"
state_dir=${PIPELINE_STATE_DIR:-"$repo_root/.pipeline"}
override_file="$state_dir/engine-override"

[ -f "$registry" ] || { echo "hiányzik a nyilvántartás: $registry" >&2; exit 2; }

expand() { printf '%s' "${1/#\~/$HOME}"; }

# Egy motor sorának mezői, TAB-bal. Üres kimenet = ismeretlen motor.
row_for() {
  grep -v '^[[:space:]]*#' "$registry" | grep -v '^name	' | awk -F'\t' -v n="$1" '$1 == n'
}

field() { printf '%s' "$1" | cut -f"$2"; }

engine_names() {
  grep -v '^[[:space:]]*#' "$registry" | grep -v '^name	' | cut -f1 | grep -v '^$'
}

active_engine() {
  [ -f "$override_file" ] && head -1 "$override_file" | tr -d '[:space:]'
}

# Elérhető-e a motor: megvan a config dir ÉS az auth (kulcsfájl vagy előfizetés).
availability() {
  local row=$1 config auth_file
  config=$(expand "$(field "$row" 3)")
  auth_file=$(field "$row" 6)
  [ -d "$config" ] || { printf 'HIÁNYZIK a profil (%s)' "$config"; return; }
  if [ "$auth_file" != "-" ]; then
    [ -r "$(expand "$auth_file")" ] || { printf 'HIÁNYZIK a kulcs (%s)' "$auth_file"; return; }
  fi
  printf 'kész'
}

case "${1:-list}" in
  list)
    active=$(active_engine)
    printf '=== Implementer-motorok (ADR 0139) ===\n'
    if [ -n "$active" ]; then
      printf 'Aktív override: %s — MINDEN kör ezzel megy.\n' "$active"
      printf 'Feloldás: tools/engine-profile.sh clear\n\n'
    else
      printf 'Nincs override — a queue `engine` oszlopa dönt körönként.\n\n'
    fi
    printf '%-17s %-8s %-24s %-11s %s\n' név harness modell állapot megjegyzés
    while IFS= read -r row; do
      [ -n "$row" ] || continue
      name=$(field "$row" 1)
      mark=" "
      [ "$name" = "$active" ] && mark="*"
      printf '%s%-16s %-8s %-24s %-11s %s\n' \
        "$mark" "$name" "$(field "$row" 2)" "$(field "$row" 4)" \
        "$(availability "$row")" "$(field "$row" 13)"
    done < <(grep -v '^[[:space:]]*#' "$registry" | grep -v '^name	')
    ;;

  show)
    active=$(active_engine)
    printf '%s\n' "${active:-<nincs override — a queue dönt>}"
    ;;

  use)
    name=${2:?használat: engine-profile.sh use <name>}
    row=$(row_for "$name")
    [ -n "$row" ] || { echo "ismeretlen motor: $name (elérhető: $(engine_names | tr '\n' ' '))" >&2; exit 2; }
    status=$(availability "$row")
    [ "$status" = "kész" ] || { echo "a(z) $name motor nem használható: $status" >&2; exit 3; }
    mkdir -p "$state_dir"
    printf '%s\n' "$name" > "$override_file"
    printf 'Aktív implementer-motor: %s (%s)\n' "$name" "$(field "$row" 4)"
    printf 'Minden további kör ezzel megy. Vissza: tools/engine-profile.sh clear\n'
    ;;

  clear)
    if [ -f "$override_file" ]; then
      previous=$(active_engine)
      rm -f "$override_file"
      printf 'Override törölve (volt: %s). A queue `engine` oszlopa dönt újra.\n' "$previous"
    else
      printf 'Nem volt override — a queue `engine` oszlopa dönt.\n'
    fi
    ;;

  env)
    # A wrapperek ezt forrásolják: a motorhoz tartozó környezet.
    name=${2:?használat: engine-profile.sh env <name>}
    row=$(row_for "$name")
    [ -n "$row" ] || { echo "ismeretlen motor: $name" >&2; exit 2; }
    harness=$(field "$row" 2)
    config=$(expand "$(field "$row" 3)")
    auth_env=$(field "$row" 5)
    auth_file=$(field "$row" 6)
    case "$harness" in
      codex)  printf 'CODEX_HOME=%s\n' "$config" ;;
      claude) printf 'CLAUDE_CONFIG_DIR=%s\n' "$config" ;;
    esac
    printf 'ENGINE_MODEL=%s\n' "$(field "$row" 4)"
    printf 'ENGINE_STALL_MINUTES=%s\n' "$(field "$row" 7)"
    printf 'ENGINE_ROUND_TIMEOUT=%s\n' "$(field "$row" 8)"
    printf 'ENGINE_CONTEXT_WINDOW=%s\n' "$(field "$row" 9)"
    printf 'ENGINE_MAX_OUTPUT=%s\n' "$(field "$row" 10)"
    if [ "$auth_env" != "-" ] && [ "$auth_file" != "-" ]; then
      key_path=$(expand "$auth_file")
      if [ -r "$key_path" ]; then
        case "$key_path" in
          *.json) printf '%s=%s\n' "$auth_env" \
                    "$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['api_key'])" "$key_path" 2>/dev/null)" ;;
          *)      printf '%s=%s\n' "$auth_env" "$(tr -d '[:space:]' < "$key_path")" ;;
        esac
      fi
    fi
    ;;

  check)
    name=${2:?használat: engine-profile.sh check <name>}
    row=$(row_for "$name")
    [ -n "$row" ] || { echo "ismeretlen motor: $name" >&2; exit 2; }
    status=$(availability "$row")
    [ "$status" = "kész" ] || { echo "$name: $status" >&2; exit 3; }
    printf '%s: profil és kulcs rendben (%s, %s)\n' \
      "$name" "$(field "$row" 2)" "$(field "$row" 4)"
    ;;

  *)
    echo "használat: engine-profile.sh [list | show | use <name> | clear | check <name> | env <name>]" >&2
    exit 2
    ;;
esac
