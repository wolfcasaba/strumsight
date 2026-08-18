#!/usr/bin/env bash
# Implementer-motor profilváltó (ADR 0140).
#
#   tools/engine-profile.sh list            # nyilvántartás + aktív + elérhetőség
#   tools/engine-profile.sh show            # csak az aktív motor neve
#   tools/engine-profile.sh use <name> [--ttl <óra>] [--reason "<szöveg>"]
#                                          # MINDEN kör ezzel a motorral megy
#   tools/engine-profile.sh clear           # vissza a queue soronkénti értékére
#   tools/engine-profile.sh check <name>    # élő füst-teszt (egy olcsó hívás)
#   tools/engine-profile.sh env <name>      # a wrapperhez: KEY=VALUE sorok
#
# `use <name> [--ttl <óra>] [--reason "<szöveg>"]` (E99-R14 / ADR 0307 §1 D1):
# az override ettől kezdve 3 soros, gépileg elemezhető:
#   engine=<név>
#   expires_at=<epoch|->
#   reason=<szöveg|->
# A lejárat `--ttl <óra>`-val adható meg; a TTL-et a meghíváskor mért
# `now + ttl_hours*3600` epoch értékre állítjuk. `--ttl 0` = azonnal lejárt
# (teszthez). Az egysoros alak (csak a motornév) TOVÁBBRA IS ÉRVÉNYES — a
# driver a hiányzó `expires_at`/`reason` sort lejárat nélküli override-ként
# kezeli, a `list` parancs kiírja a fájl korát, és a 72 órás küszöb felett
# naponta figyelmeztet (a lejárathoz képest passzív, a figyelemre aktív).
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
  local first
  [ -f "$override_file" ] || return 0
  first=$(head -1 "$override_file" | tr -d '[:space:]')
  [ -n "$first" ] || return 0
  # Az új, 3 soros alak: `engine=<név>`. A régi, egysoros alak: `<név>` —
  # utóbbit a driver a mai napig fogadja, és a `use` parancs lejárat
  # megadása nélkül is KIÍRHATJA (ha a hívó nem ad `--ttl`-t). A driver
  # szempontjából mindkettő érvényes, a `validate_engine` névre utazik.
  case "$first" in
    engine=*) printf '%s' "${first#engine=}" ;;
    *)        printf '%s' "$first" ;;
  esac
}

# A 3 soros override-fájl részei. A `engine=` kulcs a mérvadó; a többi sor
# OPCIÓ — a régi, egysoros alak (csak motornév) továbbra is támogatott, és
# `expires_at=""` + `reason=""` értékkel jelenik meg (azaz lejárat nélküli,
# nem-indokolt override).
override_field() {   # $1=kulcs (engine|expires_at|reason) → érték (vagy "-")
  local key="$1" value
  [ -f "$override_file" ] || { printf '%s' "-"; return; }
  value=$(grep -E "^${key}=" "$override_file" 2>/dev/null | head -1 | cut -d= -f2-)
  printf '%s' "${value:-}"
}

# Az override-fájl KORA órában (tizedes), a lejárattól függetlenül. A 72 órás
# küszöb mérésének alapja: a `mtime` pontos, és a `use` parancs minden
# híváskor frissíti (a TTL-lel együtt), tehát a fájl kora = a kapcsoló kora.
override_file_age_hours() {
  local mtime now
  [ -f "$override_file" ] || { printf '%s' "0"; return; }
  mtime=$(stat -c %Y "$override_file" 2>/dev/null) || { printf '%s' "0"; return; }
  now=$(date +%s)
  awk -v diff="$(( now - mtime ))" 'BEGIN { printf "%.2f", diff / 3600.0 }'
}

# Ugyanaz, mint feljebb, de a fájl útvonala paraméter (E99-R14 D2 / M3 javítás:
# a `evaluate` parancs és a tesztek egy tetszőleges útvonalra hívják, nem
# csak a globális `$override_file`-ra).
override_file_age_hours_for() {   # $1=override fájl útvonala
  local file="$1" mtime now
  [ -f "$file" ] || { printf '%s' "0"; return; }
  mtime=$(stat -c %Y "$file" 2>/dev/null) || { printf '%s' "0"; return; }
  now=$(date +%s)
  awk -v diff="$(( now - mtime ))" 'BEGIN { printf "%.2f", diff / 3600.0 }'
}

# Motor-név validáció az override-fájl olvasásához. A driver `validate_engine`
# függvénye a registry-t a `$repo_root/docs/execution/engine-registry.tsv`-n
# keresi; itt a `$registry` már eleve a fájlra mutat, ezért a registry-sor
# lekéréséhez `row_for`-t használunk. A három legacy motor (auto/minimax/codex)
# és a registry-név ugyanúgy érvényes — a `use` parancs amúgy is csak registry-
# nevet ír a fájlba, az auto/minimax/codex a queue engine oszlopából jön.
override_engine_is_valid() {   # $1=motor neve → 0 ha érvényes, 1 ha nem
  local name="$1" row
  case "$name" in
    auto | minimax | codex) return 0 ;;
    *)
      row=$(row_for "$name")
      [ -n "$row" ]
      ;;
  esac
}

# Az override-fájl állapotának kiértékelése — a motor-override blokk (és a
# tesztek) által hívott EGYETLEN belépési pont. Kimenet:
#   stdout: <motor> | EXPIRED | <empty>
#   exit:   0=live · 1=expired · 2=stale (warn) · 3=no-file · 4=invalid
# A függvény OLDALHATÁSA: a lejárt fájlt TÖRÖLI (a queue engine oszlopa lép
# életbe). A log/ntfy hívás a HÍVÓ dolga (a függvény nem ismeri a
# lánc-naplót / ntfy-topic-ot).
#
# M3 javítás: ezelőtt a `tools/round-pipeline.sh --engine-override-evaluate`
# top-level hook ugyanezt a logikát MÁSOLTA — ez a függvény az EGYETLEN
# implementáció, és a driver motor-override blokkja, valamint a tesztek is
# ezt hívják.
engine_override_evaluate() {   # $1=override fájl [$2=warn_threshold]
  local override_file="$1"
  local warn_threshold="${2:-72}"
  local raw_first engine_override expires_at age_hours above

  if [ ! -f "$override_file" ]; then
    printf '%s\n' "<empty>"
    return 3
  fi

  raw_first=$(head -1 "$override_file" | tr -d '[:space:]')
  case "$raw_first" in
    engine=*) engine_override="${raw_first#engine=}" ;;
    *)        engine_override="$raw_first" ;;
  esac
  if [ -z "$engine_override" ] || ! override_engine_is_valid "$engine_override"; then
    return 4
  fi

  expires_at=$(grep -E '^expires_at=' "$override_file" 2>/dev/null | head -1 | cut -d= -f2-)
  # Az `expires_at` jelen van és nem "-" és NEM szám — a `use` parancs
  # soha nem ír ilyet (epoch vagy "-"), tehát ez az emberi kézi
  # beavatkozás jele. Ilyenkor az óvatosság javára döntünk: a lejárat
  # ellenőrzését KIHAGYJUK, csak a kor-figyelmeztetés lép.
  if [ -n "$expires_at" ] && [ "$expires_at" != "-" ] \
      && case "$expires_at" in ''|*[!0-9]*) true ;; *) false ;; esac; then
    expires_at=""
  fi

  # 1) LEJÁRAT-ELLENŐRZÉS (E99-R14 D2): ha a TTL a múltban van, a fájl
  # TÖRLŐDIK, és a queue `engine` értéke lép életbe.
  if [ -n "$expires_at" ] && [ "$expires_at" != "-" ] \
      && [ "$(date +%s)" -ge "$expires_at" ]; then
    rm -f "$override_file"
    printf '%s\n' "EXPIRED"
    return 1
  fi

  # 2) KOR-FIGYELMEZTETÉS (E99-R14 D2): a küszöb felett WARNING, a fájl ÉL.
  if [ -z "$expires_at" ] || [ "$expires_at" = "-" ]; then
    age_hours=$(override_file_age_hours_for "$override_file")
    above=$(awk -v a="$age_hours" -v t="$warn_threshold" 'BEGIN { print (a >= t) ? 1 : 0 }')
    if [ "$above" = "1" ]; then
      printf '%s' "$engine_override"
      return 2
    fi
  fi

  printf '%s' "$engine_override"
  return 0
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

# A CLI kapcsoló csak közvetlen végrehajtás esetén fut le — a fájl
# forrásként is betölthető a függvény-könyvtár miatt (a
# `engine_override_evaluate` függvényt a driver és a tesztek is hívják
# a motor-override úton). A `BASH_SOURCE[0] != $0` minta a szokásos
# bash-irányelv: csak a SAJÁT híváskor fut a CLI.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
case "${1:-list}" in
  list)
    active=$(active_engine)
    printf '=== Implementer-motorok (ADR 0140) ===\n'
    if [ -n "$active" ]; then
      age=$(override_file_age_hours)
      expires_at=$(override_field expires_at)
      reason=$(override_field reason)
      if [ "$expires_at" = "-" ] || [ -z "$expires_at" ]; then
        expiry_line="lejárat: nincs (régi egysoros alak)"
      else
        if [ "$(date +%s)" -ge "$expires_at" ]; then
          expiry_line="lejárat: $(date -Is -d "@$expires_at") — LEJÁRT (a driver következő firingjén törlődik)"
        else
          remaining_hours=$(awk -v n="$expires_at" -v now="$(date +%s)" 'BEGIN { printf "%.1f", (n - now) / 3600.0 }')
          expiry_line="lejárat: $(date -Is -d "@$expires_at") (${remaining_hours} óra múlva)"
        fi
      fi
      printf 'Aktív override: %s — MINDEN kör ezzel megy.\n' "$active"
      printf 'Kora: %s óra · %s\n' "$age" "$expiry_line"
      [ -n "$reason" ] && [ "$reason" != "-" ] && printf 'Indoklás: %s\n' "$reason"
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
        "$(availability "$row")" "$(field "$row" 14)"
    done < <(grep -v '^[[:space:]]*#' "$registry" | grep -v '^name	')
    ;;

  show)
    active=$(active_engine)
    printf '%s\n' "${active:-<nincs override — a queue dönt>}"
    ;;

  use)
    name=${2:?használat: engine-profile.sh use <name> [--ttl <óra>] [--reason "<szöveg>"]}
    shift 2
    ttl_hours=""
    reason=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --ttl)
          [ "$#" -ge 2 ] || { echo "hiányzó érték a --ttl után" >&2; exit 2; }
          ttl_hours=$2
          shift 2
          ;;
        --reason)
          [ "$#" -ge 2 ] || { echo "hiányzó érték a --reason után" >&2; exit 2; }
          reason=$2
          shift 2
          ;;
        *)
          echo "ismeretlen kapcsoló: $1" >&2
          exit 2
          ;;
      esac
    done
    row=$(row_for "$name")
    [ -n "$row" ] || { echo "ismeretlen motor: $name (elérhető: $(engine_names | tr '\n' ' '))" >&2; exit 2; }
    status=$(availability "$row")
    [ "$status" = "kész" ] || { echo "a(z) $name motor nem használható: $status" >&2; exit 3; }
    mkdir -p "$state_dir"
    # A TTL epoch-számítás: a teszthorognak szüksége van a pontos, gépileg
    # olvasható formára, ezért `expires_at` mindig epoch (>0) vagy "-".
    if [ -n "$ttl_hours" ]; then
      case "$ttl_hours" in ''|*[!0-9.]*) echo "a TTL nem szám: $ttl_hours" >&2; exit 2 ;; esac
      expires_at=$(awk -v h="$ttl_hours" 'BEGIN { printf "%d", h * 3600 }' | awk -v now="$(date +%s)" '{ printf "%d", now + $1 }')
    else
      expires_at="-"
    fi
    [ -z "$reason" ] && reason="-"
    {
      printf 'engine=%s\n' "$name"
      printf 'expires_at=%s\n' "$expires_at"
      printf 'reason=%s\n' "$reason"
    } > "$override_file"
    printf 'Aktív implementer-motor: %s (%s)\n' "$name" "$(field "$row" 4)"
    if [ "$expires_at" = "-" ]; then
      printf 'Lejárat: nincs (régi egysoros viselkedés — a 72 órás kor-figyelmeztetés él).\n'
    else
      printf 'Lejárat: %s (TTL %.2f óra)\n' "$(date -Is -d "@$expires_at")" "$ttl_hours"
    fi
    [ "$reason" != "-" ] && printf 'Indoklás: %s\n' "$reason"
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
    # Gondolkodási szint (ADR 0173): a burkoló `-c model_reasoning_effort`-ként
    # adja tovább. "-" = ne adjunk át semmit (a provider defaultja marad).
    printf 'ENGINE_REASONING=%s\n' "$(field "$row" 13)"
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

  evaluate)
    # A driver motor-override blokkja ÉS a tesztek is ezt hívják (E99-R14 D2,
    # M3 javítás): a logika csak itt él, nincs duplikált teszthorog. A
    # kimenet: stdout = <motor> | EXPIRED | <empty>; exit 0/1/2/3/4.
    # Az opcionális $2 a warn-threshold (alap 72).
    engine_override_evaluate "$override_file" "${2:-${PIPELINE_OVERRIDE_WARN_HOURS:-72}}"
    exit $?
    ;;

  *)
    echo "használat: engine-profile.sh [list | show | use <name> [--ttl <óra>] [--reason \"<szöveg>\"] | clear | check <name> | env <name> | evaluate [<warn_threshold>]]" >&2
    exit 2
    ;;
esac
fi
