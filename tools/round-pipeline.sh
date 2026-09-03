#!/usr/bin/env bash
# Autonóm kör-pipeline driver (ADR 0087).
#
#   tools/round-pipeline.sh [--dry-run]
#
# EGY meghívás = LEGFELJEBB EGY kör, egy FRISS headless orchestrátor-sessionben.
# Cron-ból biztonságosan hívható: ha már fut egy kör, azonnal, sikerrel kilép.
#
# MIÉRT NEM egyetlen hosszú futás láncolja a köröket: az ADR 0052 "egy session
# = egy kör" szabálya a kontextus-szennyezés ellen véd. Egy friss session
# körönként ezt TELJESÍTI, nem kikerüli.
#
# A megállási szerződés (H1–H8) az ADR 0087 §2-ben van; ezt a driver NEM
# értelmezi — az orchestrátor-session dönt, és a `.pipeline/round-status`
# fájlban jelenti. A driver dolga a zár, az előfeltételek, az indítás és a
# lánc-állapot vezetése.
#
# ÖNJAVÍTÁS (ADR 0112, user-döntés 2026-08-01: "az orchestrátor MINDIG javítsa
# a hibát, a cél az autonóm fejlesztés"): a HALT már nem a lánc vége, hanem egy
# JAVÍTÓ KÖR bemenete. Halt esetén a driver friss önjavító sessiont indít, amely
# megjavítja az akadályt (akár az infrastruktúrában), a változatlan zöld kapun
# átviszi, merge-eli, és feloldja a láncot. Korlátok: körönként és halt-kódonként
# legfeljebb PIPELINE_SELFHEAL_MAX kísérlet, és a MÉRCE gyengítése (kevesebb
# teszt-fájl, módosított round-gate.sh / CI-workflow) automatikusan emberhez
# eszkalál — a mércét nem javíthatja az, akit mér (docs/LESSONS.md).
#
# Kilépési kód:
#   0 = a kör lement és merge-elődött, VAGY nem volt teendő (zár/üres sor),
#       VAGY az önjavítás sikerült és a lánc feloldva
#   3 = HALT, amit az önjavítás sem oldott fel (`.pipeline/HALTED` = az ok)
#   4 = előfeltétel nem teljesült (piszkos fa, nyitott PR, futó workflow)
#   5 = az orchestrátor-session időtúllépéssel vagy jelzés nélkül halt meg
set -uo pipefail

validate_engine() {
  case "${1:-}" in
    auto | minimax | codex) return 0 ;;
    # Motor-nyilvántartásbeli név (ADR 0140): a queue `engine` oszlopa és az
    # `engine-profile.sh use` override is hivatkozhat rá. Fail-closed marad:
    # csak a nyilvántartásban SZEREPLŐ név fogadható el.
    *)
      local registry="${BASH_SOURCE[0]%/*}/../docs/execution/engine-registry.tsv"
      [ -f "$registry" ] || return 1
      grep -v '^[[:space:]]*#' "$registry" | grep -v '^name	' \
        | cut -f1 | grep -qx "${1:-}"
      ;;
  esac
}

if [ "${1:-}" = "--validate-engine" ]; then
  [ "$#" -eq 2 ] && validate_engine "$2" || {
    echo "engine must be one of: auto | minimax | codex" >&2
    exit 2
  }
  exit 0
fi

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root" || exit 4

dry_run=0
[ "${1:-}" = "--dry-run" ] && dry_run=1

state_dir=${PIPELINE_STATE_DIR:-"$repo_root/.pipeline"}
queue_file=${PIPELINE_QUEUE_FILE:-"$repo_root/docs/execution/pipeline-queue.tsv"}
# A queue-ból származtatott completion-matrix hordozója (ADR 0112 önjavító kör,
# 2026-09-03): a merge-ág ugyanabban a commitban szinkronizálja, ahol a
# queue-sort `done`-ra billenti — l. `tools/sync-completion-matrix.py`.
completion_report_file="$repo_root/docs/sdd/program-completion-report.md"
engine_registry=${PIPELINE_ENGINE_REGISTRY:-"$repo_root/docs/execution/engine-registry.tsv"}
prompt_template="$repo_root/docs/execution/pipeline-orchestrator-prompt.md"
heal_template="$repo_root/docs/execution/pipeline-selfheal-prompt.md"
codex_preamble="$repo_root/docs/execution/pipeline-codex-orchestrator-preamble.md"
lock_file="$state_dir/lock"
halt_file="$state_dir/HALTED"
status_file="$state_dir/round-status"   # csak a default; a kör kiválasztása után kör-kulcsolt lesz
heal_status_file="$state_dir/heal-status"
heal_count_file="$state_dir/selfheal.count"
halt_reminder_file="$state_dir/halt-reminder-last"
gh_token_expiry_file="$state_dir/gh-token-expiry"
router_status_file="$state_dir/router-status"
chain_log="$state_dir/chain.log"

# A kör-állapotfájl KÖR-KULCSOLT útvonala. Egyetlen helyen dől el, hogy a
# driver, a teszthorog és a `tools/pipeline-status.sh --mark-halt` ugyanazt
# számolja — különben a router halt-átadása és a driver olvasása elcsúszna.
round_status_file_for() { printf '%s\n' "$state_dir/round-status-$1"; }
inflight_dir="$state_dir/inflight"

# --- Áteresztő-képesség (ADR 0171) ---------------------------------------
# A kapcsolók alapértelmezése a MAI viselkedés, egyetlen kivétellel: a merge
# utáni azonnali lánc-folytatás BE van kapcsolva, mert mérve (2026-08-05,
# `tools/round-metrics.py`) a lánc élettartamának 22,8%-a holtidő, és ennek
# nagy része a merge és a következő cron-firing közötti puszta várakozás.
#
#   PIPELINE_SLOTS=1        — hány kör futhat EGYSZERRE (1 = a mai lánc)
#   PIPELINE_SELF_CHAIN=1   — merge után azonnal induljon a következő firing
#   PIPELINE_MIN_FREE_GB_PER_SLOT — RAM-fedezet slotonként (OOM-védelem, L05)
slots=${PIPELINE_SLOTS:-1}
self_chain=${PIPELINE_SELF_CHAIN:-1}
min_free_gb_per_slot=${PIPELINE_MIN_FREE_GB_PER_SLOT:-6}
slot_index=1

session_timeout=${PIPELINE_SESSION_TIMEOUT:-14400}   # 4 óra: kör + javító kör + CI
heal_timeout=${PIPELINE_SELFHEAL_TIMEOUT:-10800}     # 3 óra: diagnózis + fix + CI
selfheal_enabled=${PIPELINE_SELFHEAL:-1}
selfheal_max=${PIPELINE_SELFHEAL_MAX:-3}
halt_reminder_min=${PIPELINE_HALT_REMINDER_MIN:-60}
# A `max_h` MA NEM elnémítási határ, hanem ESZKALÁCIÓS küszöb (ADR 0495 D3).
# MÉRVE 2026-08-30/31: az emlékeztető a régi szerződés szerint 24 óra után
# ELHALLGATOTT, a lánc viszont további ~24 órán át állt (576 firing, 0 kör,
# `E15-R07 / H2`). Ezért a küszöb fölött az emlékeztető nem megszűnik, hanem
# ritkul (`backoff_h`) és `urgent`-re vált.
halt_reminder_max_h=${PIPELINE_HALT_REMINDER_MAX_H:-24}
halt_reminder_backoff_h=${PIPELINE_HALT_REMINDER_BACKOFF_H:-6}
# A GitHub-PAT lejáratának előrejelzése (ADR 0495 D4). MÉRVE 2026-08-28: a
# lejárt token 57 firingen (~4,75 óra) állította meg a láncot `H-AUTH`-tal.
gh_token_warn_days=${PIPELINE_GH_TOKEN_WARN_DAYS:-7}
gh_token_probe_h=${PIPELINE_GH_TOKEN_PROBE_H:-6}
claude_bin=${CLAUDE_BIN:-claude}
# Sonnet 5 az orchestrátor-default (user-döntés 2026-08-06: „állítsd át az
# orchestrátort MINDEN RÉTEGBEN Sonnet 5 modellre, a fejlesztő agentet pedig
# állítsd vissza Terrára, mert már nincs DeepSeek kredit"). A Claude dolga a
# terv + a review + a merge-kapu; az implementer a Terra (motor-override).
# Korábbi default: claude-opus-4-8 (2026-08-04 … 2026-08-06).
# Visszakapcsolás egyetlen env-vel: PIPELINE_MODEL=claude-opus-4-8.
claude_model=${PIPELINE_MODEL:-claude-sonnet-5}

# Effort: HIGH (user-döntés 2026-08-21: „sonett 5 High orchestrator és minimax
# implementer"). A GPT-kvóta elfogyott, tehát a Codex-oldal (Sol/Terra) kiesett,
# és az EGYETLEN orchestrátor/reviewer a Claude — a keretét ezért nem égetheti a
# `max`. A 2026-08-06-i `max` azért volt vállalható, mert akkor a Codex-oldal
# még osztozott a munkán; most a `high` a mérce-tartó szint, amiből több kör fér
# egy 5 órás ablakba. Az implementer változatlanul a MiniMax M3 (saját
# API-kulcs, NEM a Claude-keret), mért gyengéit gépi őrök fogják, nem az
# orchestrátor ébersége (docs/execution/implementer-preamble-minimax.md).
# A CLI elfogadott szintjei: low | medium | high | xhigh | max (mérve:
# `claude --help`, 2.1.223). Visszaemelés egyetlen env-vel: PIPELINE_EFFORT=max.
# Az önjavító session ugyanazt a modellt kapja, mint a kör-orchestrátor — ez a
# „minden rétegben" követelmény (user-döntés 2026-08-06). A heal-kör ítéletet hoz
# (gyökérok-osztályozás, motorválasztás, mércét-nem-gyengítjük határ), ezért nem
# ereszthető lejjebb az orchestrátornál; ha valaha külön kell állítani, arra való
# a PIPELINE_SELFHEAL_MODEL.
claude_effort=${PIPELINE_EFFORT:-high}
heal_model=${PIPELINE_SELFHEAL_MODEL:-$claude_model}
# Üres, ha a heal-modellt NEM állította be explicit env — ilyenkor a heal is a
# kör-szintű párt kapja (lásd orch_pair_model).
heal_model_explicit=${PIPELINE_SELFHEAL_MODEL:+1}

# --- Kör-szintű orchestrátor-pár (user-döntés 2026-08-23) ------------------
# „a slot 1-en maradjon a Sonnet 5 high orchestrátor és a MiniMax implementer,
#  a slot 2-n pedig Opus 5 max orchestrátor és Sonnet 5 high implementer, ez
#  fogja fejleszteni az UI-t."
#
# A pár NEM a slot SORSZÁMÁHOZ kötődik, hanem a kör IMPLEMENTERÉHEZ — ez adja
# ki pontosan ugyanazt a két felállást, de fail-safe módon. Ok: hogy egy kör
# melyik fizikai slotba esik, az az időzítés esetlegessége (a driver a szabad
# slotot adja oda); sorszám-alapú kötésnél egy UI-kör az 1-es slotba érkezve
# Sonnet-orchestrátort kapna a Sonnet-implementer fölé — azaz a modell a saját
# diffjét review-zná, amit a függetlenség-őr helyesen H-INDEP-re halt. A motor
# viszont a kör sajátja (queue `engine` oszlop), tehát a párosítás mindig
# együtt utazik a körrel.
#
#   sonnet-impl implementer  → Opus 5, effort high  (UI-sáv)
#   minden más               → a globális default   (Sonnet 5, effort high)
#
# EFFORT max → high (user-döntés 2026-08-25, mért indokkal). A `max` effort a
# kör MINDKÉT Claude-oldalát (Opus 5 orchestrátor/reviewer + Sonnet 5
# implementer) UGYANARRA az előfizetésre terheli, és a heti keret lett a sáv
# szűk keresztmetszete: az utolsó 60 pipeline-session közül 18 a heti limiten
# halt meg, az E13-R16 körön 15,2 óra ment el emiatt
# (docs/execution/ch13-throughput-diagnosis.md). A user döntése: az implementer
# NEM változik (az UI-minőség a Sonnet 5-ön múlik), a megtakarítás az
# orchestrátor-oldalról jön. A mérce nem gyengül: a kör-gate, a scope-audit, a
# független review és az exact-SHA CI változatlan. Visszaemelés egyetlen
# env-vel: PIPELINE_UI_ORCH_EFFORT=max.
orch_pair_model() {    # $1=implementer motor
  case "${1:-}" in
    sonnet-impl) printf '%s' "${PIPELINE_UI_ORCH_MODEL:-claude-opus-5}" ;;
    *)           printf '%s' "$claude_model" ;;
  esac
}
orch_pair_effort() {   # $1=implementer motor
  case "${1:-}" in
    sonnet-impl) printf '%s' "${PIPELINE_UI_ORCH_EFFORT:-high}" ;;
    *)           printf '%s' "$claude_effort" ;;
  esac
}

# --- Nem futtatható motorok (user-döntés 2026-08-23) -----------------------
# „codex terra és sol már nincs többé, elfogyott az előfizetés, majd egy hónap
# múlva." A Codex-oldal egyetlen közös ChatGPT Pro kereten ül (mind gpt-5.6-*),
# tehát a három név EGYSZERRE esett ki. Egy helyen soroljuk, hogy az előfizetés
# visszatérésekor egyetlen sor törlése elég legyen.
# `${VAR-...}` (NEM `:-`): az EXPLICIT üres érték azt jelenti, hogy minden motor
# futtatható — ez a teszthorog és egyben a visszakapcsolás módja.
unrunnable_engines=${PIPELINE_UNRUNNABLE_ENGINES-codex terra sol}
engine_is_runnable() {   # $1=motor neve → 0, ha futtatható
  local name
  for name in $unrunnable_engines; do
    [ "$1" = "$name" ] && return 1
  done
  return 0
}

# A folytatás implementere a runnability-őr UTÁN. Üres kimenet = nincs pin
# (vagy elesett), tehát a queue `engine` oszlopa dönt. Külön függvény, hogy a
# `--resume-implementer` teszthorogról pontosan az mérhető legyen, ami a
# dispatch-ágon fut — ne egy hasonló, párhuzamosan karbantartott másolat.
resume_implementer_for() {   # $1=kör-azonosító
  local pinned
  pinned=$(resolve_branch_implementer "$1")
  [ -n "$pinned" ] || return 0
  engine_is_runnable "$pinned" || return 0
  printf '%s' "$pinned"
}

# A telefonos Code-lista MÉRT szabálya (2026-08-07). Egy futó Claude-session
# akkor és csak akkor jelenik meg a Claude appban, ha a session-regiszterét
# ANNAK a config-dirnek az írja, amelyikben a remote-control híd fut. A híd
# szolgáltatása (`claude-remote-control-music.service`) a
# `/home/ubuntu/.claude-rc-music` dirben él, az orchestrátor-sessiont viszont
# `env -u CLAUDE_CONFIG_DIR` indította, így a jelenléte a default
# `~/.claude/sessions/`-be került — a híd sosem láthatta. Mérés: a futó
# E05-R10 session `~/.claude/sessions/644211.json`-ban volt, a telefonról
# indított session `~/.claude-rc-music/sessions/759682.json`-ban.
# A NAIV javítás (a session a híd dirjét kapja) MÉRVE MEGBUKOTT ugyanezen a
# napon: a `.claude-rc-music` bejelentkezése a híd-processzé, sima CLI-session
# nem tudja használni — a v2.1.224 first-run folyamata teljes OAuth-ot kért
# („Paste code here if prompted"), és a heal-session el sem indult. Ugyanez a
# fal állította meg a 2026-08-05-i `rc-login-mobile` tmux-sessiont is.
# Ezért a kör-session a SAJÁT, működő bejelentkezésén marad (`~/.claude`), a
# telefonos láthatóságot pedig egy külön, ERRE a dirre kötött remote-control
# híd adja (systemd: claude-remote-control-pipeline.service).
pipeline_claude_config_dir=${PIPELINE_CLAUDE_CONFIG_DIR:-/home/ubuntu/.claude}

# Session-mód. MÉRVE 2026-08-07, a 2.1.224-es auto-frissülés UTÁN: az INTERAKTÍV
# indítás minden config-dirben belefut a first-run varázslóba, és az OAuth-ot
# kér („Paste code here if prompted") — a meglévő, érvényes bejelentkezés
# ellenére. A downgrade 2.1.223-ra sem oldotta fel: a 224-es futás perzisztens
# állapotot hagyott. A HEADLESS (-p) mód UGYANAZZAL a bejelentkezéssel viszont
# működik (mérve: `-p 'Csak ennyit válaszolj: LOGIN-OK'` → LOGIN-OK).
#
# A default INTERAKTÍV — így a kör egyszerre autonóm ÉS látható a telefonon.
#
# 2026-08-07 04:47-kor átmenetileg headless lett („I wanna the pipeline working
# without me"), mert az interaktív indítás kézi kattintást kért. MÉRVE viszont:
# mindkét felugró EGYSZERI volt (bypass-permissions figyelmeztetés,
# fullscreen-renderer ajánlat), és a bejelentkezés utáni elfogadásuk perzisztens.
# Kétszer, egymás után indított FRISS session bizonyította: a második már
# egyenesen a promptra megy, `/rc active`-kal, dialógus nélkül.
#
# Ha a CLI valaha új egyszeri dialógust vezet be, az elakadt session időkorlátra
# fut és az önjavítás veszi át — a lánc EGY env-vel azonnal életben tartható
# dialógusmentes headless módban: PIPELINE_SESSION_MODE=print.
session_mode=${PIPELINE_SESSION_MODE:-interactive}
case "$session_mode" in
  print)       session_mode_flag='-p' ;;
  interactive) session_mode_flag='' ;;
  # NEM `die` — az csak a 183. sor körül definiálódik, ez a blokk előbb fut.
  *) echo "HIBA: ismeretlen PIPELINE_SESSION_MODE: $session_mode (print | interactive)" >&2; exit 4 ;;
esac

# Orchestrátor-fallback (ADR 0115, user-döntés 2026-08-02: „a lényeg, hogy a
# pipeline ne szakadjon meg — a Terra vegye át a review-munkát"). A Terra saját
# CODEX_HOME-ban él, ahol a default model gpt-5.6-terra.
#
# user-döntés 2026-08-21: a default `none`. A ChatGPT Pro keret ELFOGYOTT, tehát
# a Codex-oldal (Terra ÉS Sol — közös auth) nem futtatható. Ez a kapcsoló a
# Codex-oldal EGYETLEN kapuja: az `orchestrator_available` a `terra`/`sol`
# ágban ezt nézi, tehát `none` mellett a lánc soha nem ad munkát halott
# motornak — inkább kivárja a Claude-ablakot (a régi, kvóta-tudatos halt-út).
# Visszakapcsolás, ha a Codex-előfizetés újraéled: PIPELINE_FALLBACK_ENGINE=terra.
fallback_engine=${PIPELINE_FALLBACK_ENGINE:-none}   # terra | none
codex_bin=${CODEX_BIN:-codex}
codex_home=${PIPELINE_FALLBACK_CODEX_HOME:-$HOME/.codex-terra}
fallback_label="Terra (gpt-5.6-terra)"

# --- Sol-orchestrátor (user-döntés 2026-08-20) -----------------------------
# A ChatGPT Pro előfizetés napokon belül lejár, és ~90% kerete bent ragadna
# („hadd fogyjon el"). Amíg él: MINDEN kör orchestrátora/reviewere a Sol
# (gpt-5.6-sol), implementere a Terra (gpt-5.6-terra) — a queue nyitott sorai
# ezzel a döntéssel `terra`-ra álltak. A Sol UGYANABBAN a CODEX_HOME-ban fut,
# mint a Terra (ugyanaz az előfizetés/auth), csak a modellje más: a driver
# explicit `-m`-mel indítja. A modell-azonosság szerinti függetlenség
# (ADR 0138 mérési kulcsa: `orchestrator_conflicts_with_implementer`) áll —
# a közös ELŐFIZETÉS-keretet a user e döntéssel tudatosan vállalta, épp a
# keret elégetése a cél. Lejárat után feloldás: PIPELINE_ORCH_ROTATION env,
# vagy az alábbi default visszaállítása `alternate`-re.
#
# LEZÁRVA 2026-08-21 (user-döntés: „lejárt a GPT kvóta"): a Pro-keret elfogyott,
# a Sol-pin megszűnt. A rotáció-fájl és a script-default `claude`, a Codex-oldalt
# a `fallback_engine=none` zárja ki. A Sol gépezete (modell-ID, címke, a `sol`
# ág az `orchestrator_available`/`orchestrator_conflicts_with_implementer`
# függvényekben) SZÁNDÉKOSAN MARAD: a nyilvántartás `sol` sora és a mérő cellák
# élnek, hogy egy esetleges Codex-újraéledés egyetlen fájl átírásával
# visszakapcsolható legyen.
sol_model=${PIPELINE_SOL_MODEL:-gpt-5.6-sol}
sol_label="Sol ($sol_model)"
claude_block_file="$state_dir/claude-blocked-until"
claude_block_seconds=${PIPELINE_CLAUDE_BLOCK_SECONDS:-18000}   # 5 órás ablak
claude_stats_cache=${PIPELINE_CLAUDE_STATS_CACHE:-$HOME/.claude/stats-cache.json}

# --- Orchestrátor-rotáció (ADR 0222, user-döntés 2026-08-11: „használjuk a
# Terrát is ugyanannyira, mint a Claude-ot") -------------------------------
# MÉRT ok: a lánc MINDEN körben a Claude-ot ültette az orchestrátor+reviewer
# székbe (a Terra csak implementált), körönként ~85 perc `--effort max`
# munkával, `azonnali lánc-folytatás`-sal szünet nélkül. Egy 5 órás ablakba
# ~3,5 kör fér — a negyedik nekimegy a falnak. Ez nem a Claude hibája, hanem
# 100%-os kihasználtság: a keret a kiosztás miatt fogy el.
#
# A rotáció ezért PROAKTÍV, nem reaktív: a körök felén eleve a Terra vezényel,
# így egyik motor kerete sem merül ki. A fallback (ADR 0115) megmarad alatta
# védőhálónak.
# user-döntés 2026-08-21 (a GPT-kvóta elfogyott): a default `claude` — a
# Codex-oldal (Sol ÉS Terra) nem futtatható, tehát nincs kinek rotálni, és az
# `alternate` minden második kört egy halott motorra ültetne. A korábbi
# defaultok: `alternate` (ADR 0222, 2026-08-11), majd `sol` (2026-08-20,
# Pro-keret égetése); env-vel és a commitolt fájllal bármikor visszaállítható.
orch_rotation=${PIPELINE_ORCH_ROTATION:-claude}   # sol | alternate | claude | terra
# A rotáció USER-DÖNTÉS, és a döntés a REPÓBAN utazik: a commitolt
# docs/execution/orchestrator-rotation fájl ERŐSEBB az env-nél
# (file > env > script-default). MÉRT ok (E99-R14 lecke): a cron
# PIPELINE_ORCH_ROTATION-t exportál, ami némán felülírná a git-en
# keresztül érkező döntést. Teszt-horog: PIPELINE_ORCH_ROTATION_FILE
# (=/dev/null → üres fájl → az env-szemantika mérhető marad).
orch_rotation_file=${PIPELINE_ORCH_ROTATION_FILE:-"$repo_root/docs/execution/orchestrator-rotation"}
orch_last_file="$state_dir/orchestrator-last"
# ADR 0242 D1: a rotáció KÖRÖNKÉNT kulcsolt, nem globális — egy kör MINDEN
# dispatchje (elhalt + újraindított is) ugyanazt az orchestrátort kapja
# vissza. Az orch_last_file marad az `alternate` léptetés hordozója, de
# kizárólag ÚJ kör ELSŐ dispatchjekor frissül (lásd next_orchestrator()).
orch_round_dir="$state_dir/orchestrator-round"
# ADR 0242 D2: melyik remote-ról olvassuk a kör-ágakat a folytatáskori
# implementer-méréshez. Tesztekben lokális bare repóra állítható.
round_remote=${PIPELINE_ROUND_REMOTE:-origin}
# Terra-vezényelt körön a Terra NEM implementálhat (ADR 0138: nem review-zheti
# a saját diffjét), ezért ilyenkor szerepet cserélnek — a Claude implementál.
# user-döntés 2026-08-11: `sonnet-impl`, mert így a két legjobb motor marad a
# körben, csak a székeket cserélik.
orch_swap_engine=${PIPELINE_ORCH_SWAP_ENGINE:-sonnet-impl}
claude_usage_file="$state_dir/claude-usage"
# USER-DÖNTÉS 2026-08-23: „nem akarom, hogy kikapcsoljon, ha a keret eléri a
# 85%-os féket — hagyd menni; kedden visszaáll, 2 napig elfut a kerettel."
# 85 → 100: a preempció gépezete MEGMARAD (a küszöb egyetlen szám), de csak a
# TELJESEN elfogyott keretnél lép be, ahol amúgy sem indulhatna semmi. Az ár,
# amit a döntés tudatosan vállal: egy kör elindulhat a maradék néhány
# százalékon, és MENET KÖZBEN halhat meg — az ilyen session H-NOSIGNAL-t hagy,
# amire a lánc önjavítót indítana, ami maga is Claude-keretet kér. A régi,
# óvatos viselkedés egyetlen env-vel visszajön: PIPELINE_CLAUDE_SESSION_PCT_MAX=85
# (101 = a fék teljes kikapcsolása).
claude_session_pct_max=${PIPELINE_CLAUDE_SESSION_PCT_MAX:-100}
# Melyik motor vigye a SOROS munkadarabot. A kör-indítási ág írja át; az
# önjavítás Claude-elsőbbséggel indul (ritka, és a zárlatokat így is nézi).
orchestrator_preference=claude

mkdir -p "$state_dir"

log() { printf '%s  %s\n' "$(date -Is)" "$*" | tee -a "$chain_log" >&2; }

# Telefon-értesítés ntfy.sh-n át (user-kérés 2026-07-31). A topic a gitignore-olt
# .pipeline/ntfy-topic fájlban él — a repó publikus, a topic nem kerülhet bele.
# Nincs topic-fájl → néma no-op (az értesítés kényelem, nem kapu).
notify() {
  local title="$1" body="$2" prio="${3:-default}"
  local topic_file="$state_dir/ntfy-topic"
  [ -f "$topic_file" ] || return 0
  curl -s -m 10 -o /dev/null \
    -H "Title: $title" -H "Priority: $prio" -H "Tags: guitar" \
    -d "$body" "https://ntfy.sh/$(cat "$topic_file")" || true
}

die() { log "HIBA: $*"; exit "${2:-4}"; }

# --- Hitelesített git-fetch a PUBLIKUS repóhoz (ADR 0495 D5) ---------------
# MÉRVE 2026-09-03 07:40–08:05: a lánc három egymást követő firingen
# `HIBA: git fetch origin main sikertelen`-nel esett ki, a szerver üzenete:
# „GitHub is temporarily limiting some unauthenticated downloads".
#
# Az ok szerkezeti, nem alkalmi: a repó PUBLIKUS, ezért a szerver a fetch-re
# nem küld 401-et — a `store` credential-helper pedig KIZÁRÓLAG kihívásra tölt.
# Vagyis MINDEN fetch-ünk hitelesítetlen volt eddig (a push nem: az mindig
# hitelesít), és a GitHub throttle-ja bármikor megállíthatja a láncot. A git
# 2.43 nem ismeri a `http.proactiveAuth`-ot (2.46+), ezért a fejlécet
# KÖRNYEZETEN át adjuk át: a titok se config-fájlba, se argv-be nem kerül, és
# a gyerekfolyamatok (klón, worktree, implementer-session git-hívásai)
# öröklik. Nincs token → néma no-op, a lánc a mai, hitelesítetlen úton megy.
setup_authenticated_git_fetch() {
  local token auth
  [ -z "${GIT_CONFIG_COUNT:-}" ] || return 0
  [ -r "$HOME/.git-credentials" ] || return 0
  token=$(sed -n 's|^https://[^:]*:\([^@]*\)@github\.com.*|\1|p' "$HOME/.git-credentials" | head -1)
  [ -n "$token" ] || return 0
  auth=$(printf 'x-access-token:%s' "$token" | base64 -w0)
  export GIT_CONFIG_COUNT=1
  export GIT_CONFIG_KEY_0="http.https://github.com/.extraheader"
  export GIT_CONFIG_VALUE_0="Authorization: Basic $auth"
}

setup_authenticated_git_fetch

# --- Rotáció-döntés a commitolt fájlból (user-döntés 2026-08-20) -----------
# Ha a docs/execution/orchestrator-rotation nem üres, az Ő értéke a rotáció —
# az operátori env csak fájl NÉLKÜL él. Üres/hiányzó fájl → env/default;
# érvénytelen tartalom → die (a fájl commitolt, a Router CI őrzi az értékét).
if [ -s "$orch_rotation_file" ]; then
  file_rotation=$(head -1 "$orch_rotation_file" | tr -d '[:space:]')
  case "$file_rotation" in
    sol | alternate | claude | terra)
      if [ -n "${PIPELINE_ORCH_ROTATION:-}" ] && [ "$PIPELINE_ORCH_ROTATION" != "$file_rotation" ]; then
        log "ROTÁCIÓ-FÁJL: a commitolt $orch_rotation_file ('$file_rotation') felülírja a PIPELINE_ORCH_ROTATION env-t ('$PIPELINE_ORCH_ROTATION')"
      fi
      orch_rotation=$file_rotation
      ;;
    *)
      die "érvénytelen rotáció-érték a $orch_rotation_file fájlban: '$file_rotation' (sol | alternate | claude | terra)"
      ;;
  esac
fi

# --- Slot-döntés a commitolt fájlból (user-döntés 2026-08-20) --------------
# „Mind a két sloton a Sol orchestrátor és a Terra implementer dolgozzon."
# A párhuzamos sávok száma UGYANOLYAN user-döntés, mint a rotáció, ezért
# ugyanazon a szerződésen utazik: a commitolt docs/execution/pipeline-slots
# ERŐSEBB az env-nél (file > env > script-default). MÉRT ok (E99-R14 lecke,
# ugyanaz az osztály, mint a rotáció-fájlnál): a cron exportálja a
# PIPELINE_SLOTS-ot, ami némán felülírná a git-en érkező döntést — a lánc
# egysávosra esne vissza anélkül, hogy ez bárhol látszana.
#
# Üres/hiányzó fájl → env/default (a mai viselkedés); nem pozitív egész →
# die (fail-closed, a Router CI a fájl értékét is őrzi). A RAM-fedezet őre
# (effective_slots) VÁLTOZATLAN: a fájl a KÉRT slotszámot mondja meg, a
# tényleges ettől lefelé térhet el, naplózott sorral (őszinte napló elve).
# Teszt-horog: PIPELINE_SLOTS_FILE (=/dev/null → env-szemantika).
slots_file=${PIPELINE_SLOTS_FILE:-"$repo_root/docs/execution/pipeline-slots"}
if [ -s "$slots_file" ]; then
  file_slots=$(head -1 "$slots_file" | tr -d '[:space:]')
  case "$file_slots" in
    '' | *[!0-9]*)
      die "érvénytelen slot-érték a $slots_file fájlban: '$file_slots' (pozitív egész)"
      ;;
  esac
  [ "$file_slots" -ge 1 ] \
    || die "érvénytelen slot-érték a $slots_file fájlban: '$file_slots' (pozitív egész)"
  if [ -n "${PIPELINE_SLOTS:-}" ] && [ "$PIPELINE_SLOTS" != "$file_slots" ]; then
    log "SLOT-FÁJL: a commitolt $slots_file ('$file_slots') felülírja a PIPELINE_SLOTS env-t ('$PIPELINE_SLOTS')"
  fi
  slots=$file_slots
fi

# --- GitHub Actions kimaradás-őr (2026-08-06, MÉRT eset) ------------------
# A GitHub 15:22-kor nyílt incidenst vezetett: „Workflow runs are failing or
# delayed in starting, and some queued jobs may time out." Következmény a
# láncra: (a) a main-egészség pirosat lát, pedig a fa jó; (b) a kör CI-je
# kétszer piros -> H5 halt -> ÖNJAVÍTÓ kör indul egy olyan hibára, amit a
# repóban nem lehet megjavítani (tiszta keret-égetés).
#
# Az őr fail-open: ha a státusz-API nem elérhető vagy nem egyértelmű, a lánc a
# mai viselkedés szerint dönt. Kikapcsolás: PIPELINE_STATUS_CHECK=0.
github_actions_degraded() {
  [ "${PIPELINE_STATUS_CHECK:-1}" = "1" ] || return 1
  local status
  status=$(curl -s -m "${PIPELINE_STATUS_TIMEOUT:-10}" \
    https://www.githubstatus.com/api/v2/components.json 2>/dev/null \
    | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    raise SystemExit(0)
for component in data.get("components", []):
    if component.get("name") == "Actions":
        print(component.get("status", ""))
        break
' 2>/dev/null)
  case "$status" in
    major_outage | partial_outage | degraded_performance)
      log "GITHUB-INCIDENS: az Actions állapota '$status' — a piros/elmaradó futások OKA külső"
      return 0
      ;;
    *) return 1 ;;
  esac
}

# --- Slotok, in-flight nyilvántartás, lánc-folytatás (ADR 0171) -----------

available_memory_gb() {   # a MOST elérhető memória GB-ban (0, ha nem mérhető)
  local kib
  kib=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null)
  case "$kib" in ''|*[!0-9]*) echo 0; return ;; esac
  echo $(( kib / 1024 / 1024 ))
}

# A slotszám MÉRT felső korlátja. A box ismert igazsága, hogy a Flutter-gate a
# memória szűk keresztmetszete (docs/LESSONS.md L05: az `analyze && test` lánc
# OOM-ot okoz ezen a gépen), ezért plusz slotot csak valódi RAM-fedezet mellett
# nyitunk. A gate-ek egymást amúgy is kizárják (a `tools/round-gate.sh` globális
# zára), ez a korlát a sessionök és a git-műveletek fedezete.
effective_slots() {
  local wanted=${1:-$slots} free affordable
  case "$wanted" in ''|*[!0-9]*) wanted=1 ;; esac
  [ "$wanted" -lt 1 ] && wanted=1
  if [ "$wanted" -eq 1 ]; then echo 1; return; fi
  free=$(available_memory_gb)
  affordable=$(( free / min_free_gb_per_slot ))
  [ "$affordable" -lt 1 ] && affordable=1
  if [ "$affordable" -lt "$wanted" ]; then
    log "SLOT-KORLÁT: ${wanted} kért slot helyett ${affordable} fér el (${free} GB szabad memória, ${min_free_gb_per_slot} GB/slot)"
    wanted=$affordable
  fi
  echo "$wanted"
}

# A slot 1 SZÁNDÉKOSAN ugyanaz a `lock` fájl, ami eddig is volt: PIPELINE_SLOTS=1
# mellett a viselkedés azonos a korábbival, és egy régi, még futó driver zárával
# is ütközik.
slot_lock_path() {
  if [ "${1:-1}" -eq 1 ]; then printf '%s\n' "$lock_file"; else printf '%s.%s\n' "$lock_file" "$1"; fi
}

# D1 (E99-R19) — main-szinkron döntés a munkafán. Kilépés nélkül fut
# (a hívó szál a `3. Előfeltételek` szakaszban van, a `die`-val ellenőrzött
# feltételek már átmentek): azonos HEAD → noop; HEAD az origin/main őse →
# `git merge --ff-only` + napló; valódi divergencia → `die` (emberi döntés).
# A részletek és a mért indoklás a hívás helyénél.
main_sync_strategy() {
  local local_head_sha remote_main_sha old_head
  local_head_sha=$(git rev-parse HEAD)
  remote_main_sha=$(git rev-parse origin/main)
  if [ "$local_head_sha" = "$remote_main_sha" ]; then
    return 0
  fi
  if git merge-base --is-ancestor "$local_head_sha" "$remote_main_sha"; then
    old_head="$local_head_sha"
    if git merge --ff-only "$remote_main_sha" 2>/dev/null; then
      log "main-szinkron: ${old_head:0:7} → $(git rev-parse --short HEAD) (ff-merge)"
      return 0
    fi
    die "a lokális main ff-merge-e nem sikerült ($old_head → $remote_main_sha) — emberi döntés kell"
  fi
  die "a lokális main eltér az origin/main-től (valódi divergencia: $local_head_sha ↛ $remote_main_sha) — emberi döntés kell"
}

inflight_add() {   # $1=kör $2=brief
  [ -f "$repo_root/tools/round-slots.py" ] || return 0
  python3 "$repo_root/tools/round-slots.py" --repo "$repo_root" --inflight "$inflight_dir" \
    inflight-add --round "$1" --brief "$2" --worktree "$repo_root" \
    --started-at "$(date -Is)" 2>/dev/null || true
}

inflight_remove() {   # $1=kör
  [ -f "$repo_root/tools/round-slots.py" ] || return 0
  python3 "$repo_root/tools/round-slots.py" --repo "$repo_root" --inflight "$inflight_dir" \
    inflight-remove --round "$1" 2>/dev/null || true
}

inflight_rounds() { ls "$inflight_dir" 2>/dev/null | grep -E '^[A-Z][0-9]{2}-R[0-9]{2}$' || true; }

# A munkafa „ismeretlen" szennyeződése — a FUTÓ körök saját, még commitolatlan
# review-artefaktuma NEM tartozik ide.
#
# MÉRVE 2026-08-23 (E13-R06 nem indult el): a kör orchesztrátora a MEGOSZTOTT fő
# fába írja a `docs/reviews/<kör>-review.md`-t (és `risk = "high"` körön a
# `-security.md`-t), amit majd a kör LANDOLÁSA commitol. Két sávnál ez azt
# jelentette, hogy amíg az egyik sáv review-fázisban van, a másik SOHA nem tud
# indulni: az E13-R05 merge-e (16:46:40) után a 16:50-es firing megszerezte a
# szabad slotot, majd `piszkos munkafa`-val meghalt a futó E09-R17
# `docs/reviews/e09-r17-review.md` fájlján — pedig a Ch13 sáv következő köre
# készen állt. Ugyanez a fájlosztály a scope-auditban MÁR mentesített
# („the reviewer's report", tools/ai_router/legacy_scope.py).
#
# A mentesség SZŰK, hogy a guard ne váljon vakká:
#   * csak IN-FLIGHT kör azonosítójára illeszkedő review/security fájl,
#   * csak `??` (untracked) állapotban — egy MÓDOSÍTOTT tracked fájl marad piszok,
#   * minden más útvonal változatlanul megállítja a láncot.
working_tree_dirt() {
  local status round slug
  # `-uall`: a git az EGÉSZÉBEN untracked könyvtárat alapból `?? docs/`-ként
  # vonja össze — ilyenkor a lenti, fájl-szintű szűrő nem illeszkedne, és a
  # mentesség némán elveszne. A fájl-szintű felsorolás ezt kizárja. A guard
  # üres/nem-üres döntése ettől NEM változik, csak a felsorolás finomsága.
  status=$(git -C "$repo_root" status --porcelain -uall 2>/dev/null)
  [ -n "$status" ] || return 0
  for round in $(inflight_rounds); do
    slug=$(printf '%s' "$round" | tr 'A-Z' 'a-z')
    status=$(printf '%s\n' "$status" | grep -vE "^\?\? docs/reviews/${slug}-[a-z]*\.md$")
  done
  printf '%s' "$status"
}

# Merge után NE várjunk a következő cron-firingre. A gyerek megvárja, amíg EZ a
# folyamat elengedi a slot-zárat, és csak utána indul — különben azonnal
# „zár foglalt"-ra futna, és a lánc-folytatás néma no-op lenne.
spawn_next_firing() {
  if [ "$self_chain" != "1" ]; then
    log "a következő firing viszi a következő kört (PIPELINE_SELF_CHAIN=0)"
    return 0
  fi
  if [ "${PIPELINE_NO_LAUNCH:-0}" = "1" ]; then
    log "PIPELINE_NO_LAUNCH=1 — a lánc-folytatás NEM indul (teszt-mód)"
    return 0
  fi
  local command=${PIPELINE_SELF_CHAIN_CMD:-"$repo_root/tools/round-pipeline.sh"}
  local parent=$$
  log "azonnali lánc-folytatás: a következő kör nem vár cron-firingre"
  # A TELJES alhéj kimenete a cron-naplóba megy: ha a szülő stdout/stderr-jét
  # örökölné, egy csővezetéken hívó szülő (pl. a teszt-futó) a gyerek haláláig
  # blokkolna az EOF-ra várva — mérve: a lánc-folytatás tesztje soha nem tért
  # vissza, mert a leválasztott gyerek nyitva tartotta a csövet.
  (
    exec 9>&-   # a slot-zár nem öröklődhet, különben a gyerek magára várna
    while kill -0 "$parent" 2>/dev/null; do sleep 1; done
    setsid bash -c "$command"
  ) >> "$state_dir/cron.log" 2>&1 < /dev/null &
  disown 2>/dev/null || true
}

# A kör pre-flightjának bemenete: a brief MÉRT gyengeségei (ADR 0171 §4).
# A `strict` szint leletei nem kapuk, hanem teendők — a brief-revízió a §2
# szerint az orchestrátor saját hatásköre, és a kör ELEJÉN a legolcsóbb.
write_brief_lint() {   # $1=kör $2=brief → a jelentés útvonala a stdouton
  local round="$1" brief="$2" report="$state_dir/brief-lint-$1.md"
  if [ ! -f "$repo_root/tools/brief-lint.py" ]; then printf '%s\n' "nincs"; return 0; fi
  python3 "$repo_root/tools/brief-lint.py" --repo "$repo_root" --brief "$brief" \
    --level strict --out "$report" >/dev/null 2>&1
  local status=$?
  if [ "$status" -ge 2 ]; then
    log "BRIEF-LINT: a(z) $round briefje base-szintű leletet ad — a pre-flight első dolga a javítása ($report)"
  elif [ "$status" -eq 1 ]; then
    log "brief-lint: $round — strict teendők a pre-flighthoz ($report)"
  fi
  [ -f "$report" ] && printf '%s\n' "$report" || printf '%s\n' "nincs"
}

# A kör MÉRT hagyaték-állapota (ADR 0112 önjavító kör, E09-R26, 2026-08-24).
# Ugyanaz az idióma, mint a brief-lint: a session nem a saját belátásából
# találgatja, hagyott-e egy korábbi, megölt session megőrzendő munkát —
# megméretlenül kapja meg. A MÉRT ok: az E09-R26 sessionjét a 20 perces
# elakadás-őr megölte, miközben a kör KÉSZ volt (review APPROVED, 0 nyitott
# lelet, Full Gate zölden a head SHA-n, PR nélkül) — a §0.2 létrán viszont
# nem volt fok erre az állapotra, tehát a `pending` queue-sor újrafutásán
# 4210 sor és egy teljes review-ciklus veszhetett volna el.
write_resume_state() {   # $1=kör → a jelentés útvonala a stdouton
  local round="$1" report="$state_dir/resume-state-$1.md" state
  if [ ! -x "$repo_root/tools/round-resume-probe.sh" ]; then printf '%s\n' "nincs"; return 0; fi
  "$repo_root/tools/round-resume-probe.sh" --round "$round" --repo "$repo_root" \
    --out "$report" >/dev/null 2>&1 || { printf '%s\n' "nincs"; return 0; }
  state=$(grep -m1 '^ÁLLAPOT: ' "$report" 2>/dev/null | cut -d' ' -f2-)
  case "$state" in
    REVIEW-APPROVED)
      log "HAGYATÉK: a(z) $round ága JÓVÁHAGYOTT review-val áll — a kör a merge-lépésnél folytatódik, NEM indul újra ($report)" ;;
    REVIEW-NYITOTT|PRE-FLIGHT)
      log "hagyaték: $round — $state, megőrzendő munka van az ágon ($report)" ;;
  esac
  [ -f "$report" ] && printf '%s\n' "$report" || printf '%s\n' "nincs"
}

# --- Friss headless orchestrátor-session futtatása -------------------------
# Az orchestrátor és az önjavító kör ugyanazt a mechanikát használja: tmux-ban
# futó agent (így látszik a telefonos Code-listában), 30 percenkénti életjel, és
# a session KÖTELESSÉGE egy jelzésfájlt írni. A visszatérési érték 0, ha a
# jelzésfájl megszületett; 1, ha nem (időtúllépés vagy néma halál).
#
# MOTORFÜGGETLEN (ADR 0115): a Claude-kvóta kimerülése nem szakíthatja meg a
# láncot — akkor ugyanezt a promptot a Codex/Terra viszi tovább.

# A Claude-kvóta kimerülésének MÉRT nyomai a session-naplóban. Szándékosan
# angol, CLI-specifikus minták: a magyar „kvóta" szó a promptokban is szerepel,
# arra illeszteni hamis pozitív lenne.
#
# MÉRVE 2026-08-11 (E06-R05, ADR 0222): a CLI ma NEM ezeket a mondatokat írja,
# hanem a pane aljára számláló bannert:
#   „You've used 97% of your session limit · resets 3:40pm (UTC) · /upgrade to k…"
# A `session-E06-R05-20260811T134634.log`-ban 11 ilyen banner van 90→97%-ig, és
# a fenti minták EGYIKE SEM illeszkedett rá. Ezért a kvóta-átadás nem lépett, a
# sessiont a 20 perces elakadás-őr lőtte le a CI-dispatch+merge közben, a kör
# H-NOSIGNAL-t kapott és két önjavító kör kellett a feloldásához. A vak
# védőháló rosszabb, mint a nincs: hamis biztonságot adott.
# MÉRVE 2026-08-25 (E13-R16, E09-R27): a CLI a HETI keret kimerülésekor a
# „You've hit your weekly limit · resets 8am (UTC)" mondatot írja ki. A minta
# `(usage|session)` csoportja erre NEM illeszkedett, ezért a kvóta-ág nem
# lépett: az utolsó 60 pipeline-session közül 18 pontosan ezen a mondaton halt
# meg, mindet H-NOSIGNAL-nak minősítve. Ára egyetlen körön (E13-R16, 1121 perc
# a 90 perces medián helyett): 4 elköltött session + önjavítási kísérlet
# 22:50–02:40 között, majd 11 óra 25 perc álló lánc kézi `--resume`-ra várva.
CLAUDE_LIMIT_PATTERN='usage limit reached|Claude usage limit|out of (usage|credits)|insufficient (credit|quota)|rate.?limit(ed)? exceeded|quota exceeded|upgrade to continue|limit will reset|you.?ve (hit|reached) your (usage|session|weekly) limit|session limit reached|used 100% of your session limit|[0-9]+-hour limit reached|weekly limit reached'

# A session-keret FOGYÁSMÉRŐJE (nem kimerülés). A bannert a CLI folyamatosan
# frissíti, ezért belőle a kimerülés ELŐTT megtudható, hogy egy ~85 perces kör
# elférne-e még a keretben. Külön minta, mert a kettő döntése különbözik: a
# kimerülés a futó sessiont állítja le, a fogyásmérő csak a KÖVETKEZŐ kör
# indítását tiltja — futó munkát nem dob el.
CLAUDE_SESSION_PCT_PATTERN='you.?ve used ([0-9]{1,3})% of your session limit'
CLAUDE_SESSION_RESET_PATTERN='resets [0-9]{1,2}(:[0-9]{2})?(am|pm)? \(UTC\)'

# A tmux pane-on futó Claude process MÉRT neve (`ps -o comm=`) ezen a boxon
# `claude` (a launcher) vagy `claude.exe` (a node bináris) — SOHA nem
# `claude-code`. A PR #84 heurisztikája erre az utóbbira illesztett, ezért a
# 10s-es türelmi idő után MINDEN élő Claude-sessiont „kvótahalálnak" minősített
# és 5 órára letiltotta a motort (mérve: 6 hamis pozitív 2026-08-03T13:35 óta,
# `.pipeline/chain.log` „Claude process már nem él"). A minta ezért a valódi
# neveket fedi, a régi `claude-code` alakot is megtartva.
CLAUDE_PROCESS_COMM_PATTERN='^claude([.-][A-Za-z0-9_-]+)?$'

# Az ELAKADÁS-ÉBRESZTŐ szövege (ADR 0112 önjavító kör, 2026-08-24). Ez megy be
# `tmux send-keys`-szel egy néma, de élő interaktív Claude-panelbe, mielőtt a
# driver megölné a sessiont. Szándékosan EGYETLEN sor és tisztán ASCII: a
# send-keys argumentumként adja át, aposztróf/újsor a beírást törné.
# A `claude` TUI beviteli doboza a gyorsan érkező, hosszú szöveget BEILLESZTÉSNEK
# kezeli, és ilyenkor a KÖZVETLENÜL utána érkező Enter ÚJ SORT ír, nem küld be.
# MÉRVE 2026-09-03: a `tmux send-keys -t <pane> "<szöveg>" Enter` alakkal a
# folytatás-prompt BENN MARADT a dobozban (négy sorra tördelve), a session
# tovább állt üresen; egy KÜLÖN, később küldött Enter azonnal beküldte. A
# driver ébresztője ugyanezt az alakot használta, tehát a „kill előtt ébressz"
# mechanizmus (HEAL E13-R14) megbízhatatlan volt (ADR 0497 D1).
NUDGE_SUBMIT_DELAY=${PIPELINE_ORCH_NUDGE_SUBMIT_DELAY:-1}

send_nudge_to_pane() {   # $1=tmux-session $2=szöveg
  local pane="$1" text="$2"
  # fd 9 (a lánc-zár) lezárása, mint a többi tmux-hívásnál (2026-08-18).
  ( exec 9>&-; tmux send-keys -t "$pane" -- "$text" ) 2>/dev/null || true
  sleep "$NUDGE_SUBMIT_DELAY"
  ( exec 9>&-; tmux send-keys -t "$pane" Enter ) 2>/dev/null || true
}

# A MÉRT 529-aláírás a session-naplóban, és mennyit nézünk a napló végéből.
API_OVERLOAD_PATTERN='API Error: 529|529 Overloaded'
OVERLOAD_TAIL_BYTES=${PIPELINE_ORCH_OVERLOAD_TAIL_BYTES:-4000}

STALL_NUDGE_TEXT=${PIPELINE_ORCH_STALL_NUDGE_TEXT:-'FOLYTASD (elakadas-ebreszto): a sessiont kulso megszakitas allitotta le, kor-jelzes nem szuletett. Ellenorizd az implementer jelzesfajljat (tools/wait-for-round.sh <munkapeldany> 540), es folytasd a kor protokolljat ott, ahol abbamaradt.'}

# A Codex/Terra fallback-ágon futó `codex exec` process MÉRT neve: `codex`
# (mérve `/proc/<pid>/comm` mintavétellel, 2026-08-15, E99-R13 H-NOSIGNAL
# önjavítás). Natív (Rust) ELF bináris ezen a boxon
# (~/.codex/packages/standalone/…/bin/codex), nem node-wrapper — a Claude-nál
# mért `.exe`/launcher-alakváltozatok itt nem alkalmazhatók.
CODEX_PROCESS_COMM_PATTERN='^codex$'

claude_unavailable_until() {   # kiírja a lejárati epoch-ot, ha érvényes zárlat van
  local until
  [ -f "$claude_block_file" ] || return 1
  until=$(cat "$claude_block_file" 2>/dev/null)
  case "$until" in ''|*[!0-9]*) return 1 ;; esac
  [ "$(date +%s)" -lt "$until" ] || { rm -f "$claude_block_file"; return 1; }
  printf '%s\n' "$until"
}

# A Claude CLI a kvótát indításkor távolról ellenőrzi, de ha a saját friss
# stats-cache-e már a CLI limit-üzenetét tartalmazza, a felesleges tmux-session
# helyett azonnal a fallbackot indítjuk. Cache hiánya vagy ismeretlen tartalma
# nem zárlat: ilyen esetben a session-napló marad a bizonyíték.
claude_stats_cache_unavailable_until() {
  [ -r "$claude_stats_cache" ] || return 1
  grep -qEi "$CLAUDE_LIMIT_PATTERN" "$claude_stats_cache" 2>/dev/null || return 1
  printf '%s\n' "$(( $(date +%s) + claude_block_seconds ))"
}

# --- Session-keret fogyásmérő (ADR 0222) ----------------------------------
# A pane-napló ANSI-vezérlőkkel teli, ezért `grep -a` és minta-illesztés, nem
# sor-alapú feldolgozás: a banner színkódok közé ékelődik.
claude_session_pct() {   # $1=session-napló → az UTOLSÓ mért százalék
  local logfile=$1 hit
  [ -r "$logfile" ] || return 1
  hit=$(grep -aoEi "$CLAUDE_SESSION_PCT_PATTERN" "$logfile" 2>/dev/null | tail -n 1)
  [ -n "$hit" ] || return 1
  printf '%s' "$hit" | grep -oE '[0-9]{1,3}' | head -n 1
}

# A banner a pontos reset-időt is kiírja (`resets 3:40pm (UTC)`). Ezt használva
# a zárlat nem vak 5 órás felülbecslés, hanem a tényleges ablakhoz igazodik —
# a Claude a reset másodpercében újra sorra kerülhet. Ismeretlen alakra üres a
# kimenet, és marad a régi, biztonságos felülbecslés.
claude_session_reset_epoch() {   # $1=session-napló → epoch
  local logfile=$1 raw clock epoch now
  [ -r "$logfile" ] || return 1
  raw=$(grep -aoEi "$CLAUDE_SESSION_RESET_PATTERN" "$logfile" 2>/dev/null | tail -n 1)
  [ -n "$raw" ] || return 1
  clock=$(printf '%s' "$raw" | sed -E 's/^[Rr]esets //; s/ \(UTC\)$//')
  epoch=$(date -u -d "today $clock" +%s 2>/dev/null) || return 1
  [ -n "$epoch" ] || return 1
  now=$(date +%s)
  # A kiírt idő a KÖVETKEZŐ resetet jelenti; ha mára már elmúlt, holnapi.
  [ "$epoch" -le "$now" ] && epoch=$(( epoch + 86400 ))
  printf '%s\n' "$epoch"
}

record_claude_usage() {   # $1=session-napló → a mért keret-állás kiírása
  local logfile=$1 pct reset
  pct=$(claude_session_pct "$logfile") || return 0
  reset=$(claude_session_reset_epoch "$logfile" || true)
  printf 'pct=%s\nreset=%s\nmeasured=%s\nlog=%s\n' \
    "$pct" "${reset:-}" "$(date +%s)" "$logfile" > "$claude_usage_file"
  log "Claude session-keret: ${pct}% elhasználva${reset:+ · reset $(date -Is -d "@$reset")}"
}

# Preemption: egy kör ~85 perc orchestrátor-munka, ezt nem szabad a keret
# maradék néhány százalékán elindítani. A futó munkát viszont SOHA nem dobjuk
# el emiatt — ez csak az indítást tiltja.
claude_usage_block_until() {
  local pct reset measured
  [ -r "$claude_usage_file" ] || return 1
  pct=$(sed -n 's/^pct=//p' "$claude_usage_file" | head -1)
  case "$pct" in ''|*[!0-9]*) return 1 ;; esac
  [ "$pct" -ge "$claude_session_pct_max" ] || return 1
  reset=$(sed -n 's/^reset=//p' "$claude_usage_file" | head -1)
  case "$reset" in
    ''|*[!0-9]*)
      measured=$(sed -n 's/^measured=//p' "$claude_usage_file" | head -1)
      case "$measured" in ''|*[!0-9]*) return 1 ;; esac
      reset=$(( measured + claude_block_seconds ))
      ;;
  esac
  [ "$(date +%s)" -lt "$reset" ] || return 1
  printf '%s\n' "$reset"
}

# --- Orchestrátor-rotáció (ADR 0222 + 0242 D1) ----------------------------
# Kiírja, MELYIK motor vezényelje a következő kört: `claude` vagy `terra`.
# A zárlatok felülírják a rotációt (kimerült keretre nem osztunk munkát).
#
# ADR 0242 D1: opcionális $1=kör-azonosítóval az állapot KÖRÖNKÉNT kulcsolt
# (<state_dir>/orchestrator-round/<ROUND>). Az adott kör ELSŐ hívása rögzíti
# a döntést (és — csak ekkor — lépteti a globális orch_last_file-t is); MINDEN
# további hívás UGYANAZT a rögzített értéket adja vissza, léptetés nélkül. Ez
# védi a mid-round halt + újraindítás mintát (mért eset: E06-R23 H-INDEP,
# 4 óra 35 perc állásidő egy kész, gate-zöld kör fölött).
#
# $1 NÉLKÜL a viselkedés BIT-RE AZONOS a D1 előttivel (5.4): a `--next-
# orchestrator` argumentum nélküli teszthorga és a `resolve_independent_
# engine`/`--orchestrator-engine` belső hívásai ezt az alakot használják, és
# nem kaphatnak kör-kulcsolt állapotot.
next_orchestrator() {   # [$1=kör-azonosító] → claude | terra | sol
  local round="${1:-}" round_file="" last value
  if [ -n "$round" ]; then
    round_file="$orch_round_dir/$round"
    if [ -r "$round_file" ]; then
      head -1 "$round_file" | tr -d '[:space:]'
      printf '\n'
      return 0
    fi
  fi

  if [ "$fallback_engine" = "none" ]; then
    value=claude
  elif [ "$orch_rotation" = "sol" ]; then
    # A Sol a Codex-oldalon fut, nem a Claude-keretből — a Claude-zárlat
    # ezért nem érinti; a pin a zárlat-mérés ELŐTT dől el (user-döntés
    # 2026-08-20: minden kört a Sol vezényel, amíg a Pro-keret él).
    value=sol
  elif claude_unavailable_until >/dev/null || claude_usage_block_until >/dev/null; then
    value=terra
  else
    case "$orch_rotation" in
      claude) value=claude ;;
      terra)  value=terra ;;
      *)
        last=''
        [ -r "$orch_last_file" ] && last=$(head -1 "$orch_last_file" | tr -d '[:space:]')
        if [ "$last" = "claude" ]; then value=terra; else value=claude; fi
        ;;
    esac
  fi

  if [ -n "$round_file" ]; then
    mkdir -p "$orch_round_dir"
    printf '%s\n' "$value" > "$round_file"
    printf '%s\n' "$value" > "$orch_last_file"
  fi
  printf '%s\n' "$value"
}

# A tmux-session felügyelete a jelzésfájlig. Egyetlen paraméterben kapja a
# héj-parancsot, ezért motorfüggetlen.
run_tmux_session() {
  local tmux_session="$1" shell_command="$2" session_log="$3" signal_file="$4"
  local timeout_s="$5" label="$6" watch_claude_limit="${7:-0}"
  local fallback_process_pattern="${8:-}"
  local deadline pinger_pid claude_started_at claude_limit_seen=0 pane_tty
  local stall_seconds log_age
  local nudge_budget nudges_sent=0 last_nudge_at=0 stall_reference nudge_tty
  local overload_seconds overload_budget active_stall_seconds active_nudge_budget

  # TESZT-BIZTOSÍTÉK (ADR 0138, MÉRVE 2026-08-05). A `tools/tests/` teljes
  # firinget futtató esetei izolált `PIPELINE_STATE_DIR`-t kapnak, de a
  # kör-indítási ág a VALÓDI `docs/execution/pipeline-queue.tsv`-t olvassa —
  # így egy tiszta `main`-ről futtatott teszt ÉLES orchestrátor-sessiont és
  # `codex exec`-et indított az E04-R10-re (a félkész implementer-munka
  # elveszett, a kör-branch újra pre-flightolva lett). A tesztfájl fejlécei
  # ezt a veszélyt már ismerték ("confirmed: it happened … had to be killed
  # by hand"), de csak a self-heal ágra védekeztek stub-okkal.
  #
  # Ez a kapcsoló nem heurisztika, hanem szerződés: `PIPELINE_NO_LAUNCH=1`
  # mellett a driver MINDEN egyéb logikája lefut, de sessiont soha nem indít.
  if [ "${PIPELINE_NO_LAUNCH:-0}" = "1" ]; then
    log "PIPELINE_NO_LAUNCH=1 — a(z) $label session NEM indul (teszt-mód)"
    return 90
  fi

  # MÉRT hiba (2026-08-18): a tmux SZERVER a kliens FD-jeit örökli, tehát a
  # slot-zár (fd 9) nála marad — és a szerver túléli a kört (amíg BÁRMELYIK
  # tmux session él). Következmény: az E07-R22 driver által 18:13-kor indított
  # szerver 19:47-es merge után is fogta a `.pipeline/lock`-ot, ezért a
  # `PIPELINE_SLOTS=2` mellett az 1-es slot TARTÓSAN foglalt volt — a lánc
  # egysávosra esett vissza anélkül, hogy ez bárhol látszott volna.
  #
  # A driver ezt a hibaosztályt már ismerte (a pinger-alhéj fd 9-et zár,
  # 2026-07-31), csak a tmux-hívások maradtak ki. Az alhéj mindhármat lefedi.
  (
    exec 9>&-
    tmux kill-session -t "$tmux_session" 2>/dev/null || true
    tmux new-session -d -s "$tmux_session" bash
    tmux pipe-pane -t "$tmux_session" -o "cat >> $session_log"
    tmux send-keys -t "$tmux_session" "$shell_command" Enter
  )
  log "session indult: $tmux_session (mód: $session_mode) → $session_log"

  (
    # fd 9 (a lánc-zár) lezárása az alhéjban — különben a pinger örökli, és a
    # driver halála után árvaként fogva tartaná a zárat (mérve 2026-07-31).
    exec 9>&-
    local elapsed=0
    while sleep 1800; do
      elapsed=$(( elapsed + 30 ))
      notify "⏳ $label még fut" "${elapsed} perce dolgozik" low
    done
  ) &
  pinger_pid=$!

  deadline=$(( $(date +%s) + timeout_s ))
  claude_started_at=$(date +%s)
  stall_seconds=${PIPELINE_ORCH_STALL_SECONDS:-$(( ${PIPELINE_ORCH_STALL_MINUTES:-20} * 60 ))}
  nudge_budget=${PIPELINE_ORCH_STALL_NUDGES:-1}
  # API 529 („Overloaded") esetén a session BIZONYÍTOTTAN üres prompton áll —
  # nem gondolkodik. Ilyenkor nincs értelme kivárni a teljes néma ablakot
  # (ADR 0497 D2): rövidebb küszöb és nagyobb ébresztés-keret, mert egy külső
  # kimaradás ismétlődhet.
  overload_seconds=${PIPELINE_ORCH_OVERLOAD_SECONDS:-120}
  overload_budget=${PIPELINE_ORCH_OVERLOAD_NUDGES:-4}
  while [ ! -f "$signal_file" ]; do
    if [ "$(date +%s)" -ge "$deadline" ]; then
      log "időkorlát lejárt ($label) — a tmux-sessiont leállítjuk"
      break
    fi
    if [ "$watch_claude_limit" = "1" ] \
      && tail -n "${PIPELINE_CLAUDE_LIMIT_LOG_LINES:-80}" "$session_log" 2>/dev/null \
        | grep -qEi "$CLAUDE_LIMIT_PATTERN"; then
      log "KVÓTA: Claude limit-nyom érkezett a futó session-naplóba — a tmux-sessiont azonnal leállítjuk"
      claude_limit_seen=1
      break
    fi
    if ! tmux has-session -t "$tmux_session" 2>/dev/null; then
      # meghalt jelzés nélkül — türelmi kör a fájl-írás versenyére, aztán ki
      sleep 15
      break
    fi
    if [ "$watch_claude_limit" = "1" ] \
      && [ "$(( $(date +%s) - claude_started_at ))" -ge "${PIPELINE_CLAUDE_PROCESS_GRACE_SECONDS:-10}" ]; then
      pane_tty=$(tmux list-panes -t "$tmux_session" -F '#{pane_tty}' 2>/dev/null | head -n 1)
      if [ -n "$pane_tty" ] \
        && ! ps -t "${pane_tty#/dev/pts/}" -o comm= 2>/dev/null \
          | grep -qE "$CLAUDE_PROCESS_COMM_PATTERN"; then
        printf '%s\n' "$(( $(date +%s) + claude_block_seconds ))" > "$claude_block_file"
        log "KVÓTA: a Claude process már nem él a tmux pane-on — a fallback veszi át"
        claude_limit_seen=1
        break
      fi
    fi
    # ELAKADÁS-GYORSÍTÓ, motorfüggetlen (mérve E99-R13 H-NOSIGNAL önjavítás,
    # 2026-08-15): a Codex/Terra fallback-ágon a pane EGYETLEN előtér-parancsot
    # kap (`codex exec …`). Ha az a folyamat magától, jelzésfájl nélkül kilép,
    # a tmux-session — a mögötte élő üres shell miatt — ÉLETBEN marad, tehát a
    # fenti `has-session` ág sosem kapja el, és a fenti Claude-ellenőrzés sem
    # vonatkozik rá (kvóta-specifikus, `watch_claude_limit=1`-hez kötött).
    # Mérve: a `codex exec` process 11:03:26-kor lépett ki (a session-napló
    # utolsó írása), a driver csak 11:23:38-kor, a lenti 20 perces
    # log-elakadás-őrnél ismerte fel — 20 perc tétlen várakozás egy már holt
    # folyamatra, a láncot közben 5 percenként lezáró cron-firing mellett.
    # Ugyanaz a `ps -t <pane_tty>` mérés, mint a Claude-ágon, csak
    # motorfüggetlenül: a hívó adja meg, milyen process-nevet vár — üres minta
    # (a Claude-hívás nem ad 8. argumentumot) = nincs ellenőrzés, a Claude-ág
    # viselkedése változatlan.
    if [ -n "$fallback_process_pattern" ] \
      && [ "$(( $(date +%s) - claude_started_at ))" -ge "${PIPELINE_CLAUDE_PROCESS_GRACE_SECONDS:-10}" ]; then
      pane_tty=$(tmux list-panes -t "$tmux_session" -F '#{pane_tty}' 2>/dev/null | head -n 1)
      if [ -n "$pane_tty" ] \
        && ! ps -t "${pane_tty#/dev/pts/}" -o comm= 2>/dev/null \
          | grep -qE "$fallback_process_pattern"; then
        log "ELAKADÁS-GYORSÍTÓ: a(z) $label motor-folyamata jelzésfájl nélkül kilépett a tmux pane-en — nem várjuk ki a $(( stall_seconds / 60 ))-perces elakadás-őrt"
        break
      fi
    fi
    # ELAKADÁS-ŐR (mérve E05-R17 H-NOSIGNAL: egy "API Error: Server error
    # mid-response" után a tmux-session ÉLETBEN maradt, de a panel 1h24m-ig
    # néma volt — a fenti ellenőrzések egyike sem kapta el, a driver csak a
    # 4 órás abszolút időkorlátnál vette észre. Valódi munka alatt a
    # pane-újrarajzolás (spinner, eltelt-idő számláló) folyamatosan ír, ezért
    # a session-napló hosszan tartó változatlansága élő session mellett is
    # megbízhatóan elakadást jelez — ugyanaz a minta, mint az implementer
    # oldali MM_STALL_MINUTES (tools/mm-round.sh), csak log-mtime alapon,
    # mert ez a session interaktív (nincs stream-json esemény, ami írna).
    #
    # ELAKADÁS-ÉBRESZTŐ (mérve E13-R14 H-NOSIGNAL, önjavítás 2026-08-24): a
    # néma panel NEM mindig halott munka. Az E13-R14 orchestrátor-sessionje
    # 15:48:46-kor előtérbe tette a `tools/wait-for-round.sh … 540` hívást,
    # 15:51:11-kor viszont KÍVÜLRŐL érkezett rá egy megszakítás (a
    # `4615efa7…` naplóban: "The user doesn't want to proceed with this tool
    # use" + "[Request interrupted by user for tool use]") — követő prompt
    # nélkül. A session, a tmux és a Claude-process is ÉLT, csak üres
    # prompton állt, ezért egyetlen fenti ellenőrzés sem kapta el, a panel
    # pedig nem írt többet. Közben az implementer 16:03:33-kor `status=done`
    # jelzéssel BEFEJEZTE a kört — a driver mégis 16:11:39-kor megölte a
    # sessiont és H-NOSIGNAL-t jelzett, elejtve egy kész kört.
    #
    # Egy üres prompton álló interaktív session önmagától sosem indul újra:
    # csak KÍVÜLRŐL éleszthető. Ezért a felismerés (fent) mellé egy korlátos
    # ÉBRESZTÉS kerül: ha a panel néma, de a pane-en még ÉL egy interaktív
    # Claude-process, a driver előbb beküld egy folytatás-promptot, és csak a
    # következő teljes elakadás-ablak letelte után öl. Az őr így nem szűnik
    # meg — a `break` továbbra is a terminális ág —, csak nem az ELSŐ néma
    # ablak dönt. Az ébresztés-keret 0-ra állítva a régi viselkedést adja.
    if [ -f "$session_log" ]; then
      # A referencia a napló mtime-ja ÉS az utolsó ébresztés közül a
      # későbbi: egy ébresztés után az őr teljes új ablakot ad a válaszra,
      # anélkül hogy a naplófájlt (a bizonyítékot) hamis mtime-mal írnánk át.
      stall_reference=$(stat -c %Y "$session_log" 2>/dev/null || date +%s)
      [ "$last_nudge_at" -gt "$stall_reference" ] && stall_reference=$last_nudge_at
      log_age=$(( $(date +%s) - stall_reference ))
      # MÉRT eset (2026-09-03 13:31, E15-R12 + E16-R02): mindkét session
      # `API Error: 529 Overloaded`-del ZÁRTA a turnjét („Cooked for 1h 22m
      # 21s"), és üres prompton állt. A 20 perces néma ablak ilyenkor tiszta
      # veszteség — a session nem dolgozik, csak vár.
      active_stall_seconds=$stall_seconds
      active_nudge_budget=$nudge_budget
      if tail -c "$OVERLOAD_TAIL_BYTES" "$session_log" 2>/dev/null \
        | grep -qaE "$API_OVERLOAD_PATTERN"; then
        active_stall_seconds=$overload_seconds
        active_nudge_budget=$overload_budget
      fi
      if [ "$log_age" -ge "$active_stall_seconds" ]; then
        nudge_tty=$(tmux list-panes -t "$tmux_session" -F '#{pane_tty}' 2>/dev/null | head -n 1)
        # Csak interaktív Claude-panelt van értelme ébreszteni: annak van
        # prompt-doboza. A `codex exec` a promptot argv-ből kapja, stdin-re
        # küldött szöveg nem éri el — ott a minta nem illeszkedik, tehát a
        # viselkedés változatlanul az azonnali `break`.
        if [ "$nudges_sent" -lt "$active_nudge_budget" ] \
          && [ -n "$nudge_tty" ] \
          && ps -t "${nudge_tty#/dev/pts/}" -o comm= 2>/dev/null \
            | grep -qE "$CLAUDE_PROCESS_COMM_PATTERN"; then
          nudges_sent=$(( nudges_sent + 1 ))
          last_nudge_at=$(date +%s)
          log "ELAKADÁS-ÉBRESZTŐ ($nudges_sent/$active_nudge_budget): a(z) $label panelje $(( active_stall_seconds / 60 )) perce néma, de a Claude-process ÉL — folytatás-prompt megy be, még nem öljük meg a sessiont"
          # fd 9 (a lánc-zár) lezárása, mint a többi tmux-hívásnál (2026-08-18).
          send_nudge_to_pane "$tmux_session" "$STALL_NUDGE_TEXT"
        else
          log "ELAKADÁS: a(z) $label session-naplója $(( active_stall_seconds / 60 )) perce nem változott (élő tmux-session, jelzés nélkül) — leállítjuk, nem várjuk ki a teljes időkorlátot"
          break
        fi
      fi
    fi
    sleep 30
  done
  tmux kill-session -t "$tmux_session" 2>/dev/null || true
  kill "$pinger_pid" 2>/dev/null

  # A keret-állás kimérése a session naplójából (ADR 0222). Itt, a session
  # VÉGÉN mérünk, mert a következő kör indítási döntéséhez kell — a futó
  # munkát a fogyásmérő sosem szakítja meg.
  if [ "$watch_claude_limit" = "1" ]; then
    record_claude_usage "$session_log"
  fi

  [ "$claude_limit_seen" = "1" ] && return 0
  [ -f "$signal_file" ]
}

# A Codex/Terra ugyanazt a prompt-fájlt kapja, egy motor-specifikus előszóval
# (nincs skill-rendszere, ezért a skill-fájlt fájlként olvassa el).
codex_prompt_file() {
  local prompt_file="$1" merged="${prompt_file%.md}-codex.md"
  {
    [ -f "$codex_preamble" ] && cat "$codex_preamble"
    printf '\n---\n\n'
    cat "$prompt_file"
  } > "$merged"
  printf '%s\n' "$merged"
}

# A self-heal motorválasztása a nyilvántartást olvassa, nem a kör queue-sorát:
# a heal orchestrátor mai, rögzített identitása `sonnet-impl` (E99-R15 §0.0).
selfheal_engine_registry_row() {   # $1=motor neve → a nyilvántartás sora
  [ -r "$engine_registry" ] || return 1
  grep -v '^[[:space:]]*#' "$engine_registry" | grep -v '^name	' \
    | awk -F'\t' -v n="$1" '$1 == n {print; found=1; exit} END {exit !found}'
}

selfheal_engine_field() { printf '%s' "$1" | cut -f"$2"; }

selfheal_engine_path() { printf '%s' "${1/#\~/$HOME}"; }

selfheal_engine_is_available() {   # $1=registry sor → 0, ha statikusan futtatható
  local row="$1" harness config auth_file
  harness=$(selfheal_engine_field "$row" 2)
  config=$(selfheal_engine_path "$(selfheal_engine_field "$row" 3)")
  auth_file=$(selfheal_engine_field "$row" 6)
  case "$harness" in
    claude | codex) ;;
    *) return 1 ;;
  esac
  [ -d "$config" ] || return 1
  [ "$auth_file" = "-" ] || [ -r "$(selfheal_engine_path "$auth_file")" ]
}

# Az utolsó önjavító próbálkozás keres egy statikusan elérhető, más modellű
# motort. Nincs jelölt → visszaadja az eredetit: fail-open a mai viselkedésre.
heal_engine_for_attempt() {   # $1=kör $2=halt-kód $3=kísérlet $4=kör-motor
  local attempt="$3" round_engine="$4" current_row current_model
  local candidate row candidate_model

  if [ "$attempt" -lt "$selfheal_max" ]; then
    printf '%s\n' "$round_engine"
    return 0
  fi

  current_row=$(selfheal_engine_registry_row "$round_engine") || {
    printf '%s\n' "$round_engine"
    return 0
  }
  current_model=$(selfheal_engine_field "$current_row" 4)
  while IFS= read -r candidate; do
    [ -n "$candidate" ] || continue
    row=$(selfheal_engine_registry_row "$candidate") || continue
    candidate_model=$(selfheal_engine_field "$row" 4)
    [ "$candidate" != "$round_engine" ] || continue
    [ "$candidate_model" != "$current_model" ] || continue
    selfheal_engine_is_available "$row" || continue
    printf '%s\n' "$candidate"
    return 0
  done < <(grep -v '^[[:space:]]*#' "$engine_registry" | grep -v '^name	' | cut -f1)

  printf '%s\n' "$round_engine"
}

pipeline_now_epoch() {
  case "${PIPELINE_TEST_NOW:-}" in
    '' ) date +%s ;;
    *[!0-9]* ) date +%s ;;
    * ) printf '%s\n' "$PIPELINE_TEST_NOW" ;;
  esac
}

halt_stall_hours() {   # → hány EGÉSZ órája áll a lánc; 1, ha nem mérhető
  local now halted_at halted_epoch
  now=$(pipeline_now_epoch)
  halted_at=$(grep -m1 '^halted_at=' "$halt_file" 2>/dev/null | cut -d= -f2-)
  [ -n "$halted_at" ] || return 1
  halted_epoch=$(TZ=UTC date -d "$halted_at" +%s 2>/dev/null) || return 1
  printf '%s\n' "$(( (now - halted_epoch) / 3600 ))"
}

halt_reminder_priority() {   # → a MOST esedékes emlékeztető ntfy-prioritása
  local hours
  hours=$(halt_stall_hours) || { printf 'high\n'; return 0; }
  case "$halt_reminder_max_h" in ''|*[!0-9]*) printf 'high\n'; return 0 ;; esac
  if [ "$hours" -ge "$halt_reminder_max_h" ]; then printf 'urgent\n'; else printf 'high\n'; fi
}

halt_reminder_due() {   # $1=kör $2=halt-kód → 0, ha MOST kell küldeni
  local round="$1" halt_code="$2" now halted_at halted_epoch
  local last_line last_reminder min_seconds max_seconds interval_seconds
  now=$(pipeline_now_epoch)
  halted_at=$(grep -m1 '^halted_at=' "$halt_file" | cut -d= -f2-)
  halted_epoch=$(TZ=UTC date -d "$halted_at" +%s 2>/dev/null) || return 0
  case "$halt_reminder_min" in ''|*[!0-9]*) return 0 ;; esac
  case "$halt_reminder_max_h" in ''|*[!0-9]*) return 0 ;; esac
  case "$halt_reminder_backoff_h" in ''|*[!0-9]*) return 0 ;; esac
  min_seconds=$(( halt_reminder_min * 60 ))
  max_seconds=$(( halt_reminder_max_h * 60 * 60 ))
  # A küszöb fölött az emlékeztető NEM szűnik meg — ritkul és `urgent` lesz.
  if [ "$now" -lt "$(( halted_epoch + max_seconds ))" ]; then
    interval_seconds=$min_seconds
  else
    interval_seconds=$(( halt_reminder_backoff_h * 60 * 60 ))
  fi

  [ -f "$halt_reminder_file" ] || return 0
  last_line=$(cat "$halt_reminder_file")
  case "$last_line" in
    "$round|$halt_code|"*) last_reminder=${last_line##*|} ;;
    *) return 0 ;;
  esac
  case "$last_reminder" in ''|*[!0-9]*) return 0 ;; esac
  [ "$now" -ge "$(( last_reminder + interval_seconds ))" ]
}

record_halt_reminder() {   # $1=kör $2=halt-kód
  printf '%s|%s|%s\n' "$1" "$2" "$(pipeline_now_epoch)" > "$halt_reminder_file"
}

# A választott motor a nyilvántartás saját harnessén fut. A MiniMax-kulcsot az
# engine-profile csak a tmux-beli shellben olvassa be, így nem kerül argv-be.
run_selfheal_session() {   # $1=motor $2=tmux-név $3=prompt $4=log $5=jelzés $6=timeout $7=label
  local engine="$1" tmux_session="$2" prompt_file="$3" session_log="$4"
  local signal_file="$5" timeout_s="$6" label="$7"
  local row harness config_dir model auth_env codex_prompt runner profile_env

  row=$(selfheal_engine_registry_row "$engine") || {
    log "az önjavító motor nincs a nyilvántartásban: $engine"
    return 1
  }
  selfheal_engine_is_available "$row" || {
    log "az önjavító motor nem elérhető: $engine"
    return 1
  }
  harness=$(selfheal_engine_field "$row" 2)
  config_dir=$(selfheal_engine_path "$(selfheal_engine_field "$row" 3)")
  model=$(selfheal_engine_field "$row" 4)
  auth_env=$(selfheal_engine_field "$row" 5)
  rm -f "$signal_file"

  case "$harness" in
    claude)
      runner="CLAUDE_CONFIG_DIR='$config_dir' DISABLE_AUTOUPDATER=1 $claude_bin $session_mode_flag --permission-mode bypassPermissions --model '$model' --effort $claude_effort 'Pipeline $label — olvasd el es kovesd pontosan a promptot ebbol a fajlbol: $prompt_file'"
      case "$model" in
        claude-* | sonnet-* | opus-* | haiku-*) ;;
        *)
          profile_env="eval \"\$(bash '$repo_root/tools/engine-profile.sh' env '$engine')\";"
          runner="$profile_env export ANTHROPIC_BASE_URL='https://api.minimax.io/anthropic'; export ANTHROPIC_AUTH_TOKEN=\"\${$auth_env:-}\"; $runner"
          ;;
      esac
      run_tmux_session "$tmux_session" "$runner" "$session_log" "$signal_file" \
        "$timeout_s" "$label" 0 "$CLAUDE_PROCESS_COMM_PATTERN"
      ;;
    codex)
      command -v "$codex_bin" >/dev/null || {
        log "nincs $codex_bin CLI — az önjavító motor nem indítható"
        return 1
      }
      codex_prompt=$(codex_prompt_file "$prompt_file")
      runner="CODEX_HOME='$config_dir' $codex_bin exec -m '$model' -C '$repo_root' -s danger-full-access \"\$(cat '$codex_prompt')\" < /dev/null"
      run_tmux_session "$tmux_session" "$runner" "$session_log" "$signal_file" \
        "$timeout_s" "$label" 0 "${CODEX_PROCESS_COMM_PATTERN:-codex}"
      ;;
    *)
      log "nem támogatott önjavító harness: $harness"
      return 1
      ;;
  esac
}

# Egy orchestrátori munkadarab levezénylése: elsőként Claude, kvótazárlat vagy
# kvótára utaló néma halál esetén Codex/Terra. 0 = van jelzésfájl.
run_orchestrator_session() {
  local tmux_session="$1" prompt_file="$2" session_log="$3" signal_file="$4"
  local timeout_s="$5" label="$6" session_model="${7:-$claude_model}"
  local session_effort="${8:-$claude_effort}"
  local blocked_until codex_prompt
  # A Codex-oldali orchestrátor alakja: Terra (default model, ADR 0115/0222)
  # vagy Sol (user-döntés 2026-08-20, explicit `-m $sol_model` UGYANABBAN a
  # CODEX_HOME-ban — az auth közös, csak a modell más).
  local orch_codex_label="$fallback_label" orch_model_args=""
  if [ "$orchestrator_preference" = "sol" ]; then
    orch_codex_label=$sol_label
    orch_model_args=" -m $sol_model"
  fi

  rm -f "$signal_file"

  if { [ "$orchestrator_preference" = "terra" ] || [ "$orchestrator_preference" = "sol" ]; } \
     && [ "$fallback_engine" != "none" ]; then
    log "ROTÁCIÓ: ezt a munkadarabot a $orch_codex_label vezényli (PIPELINE_ORCH_ROTATION=$orch_rotation)"
  elif blocked_until=$(claude_unavailable_until); then
    log "a Claude-kvóta zárlat alatt van $(date -Is -d "@$blocked_until")-ig — a kört a $fallback_label viszi"
  elif blocked_until=$(claude_usage_block_until); then
    log "a Claude session-kerete $(sed -n 's/^pct=//p' "$claude_usage_file" | head -1)%-on áll (küszöb: ${claude_session_pct_max}%) — a kört a $fallback_label viszi $(date -Is -d "@$blocked_until")-ig"
  elif blocked_until=$(claude_stats_cache_unavailable_until); then
    printf '%s\n' "$blocked_until" > "$claude_block_file"
    log "a Claude stats-cache aktív kvótazárlatot jelez — a kört a $fallback_label viszi"
  else
    if run_tmux_session "$tmux_session" \
      "CLAUDE_CONFIG_DIR=$pipeline_claude_config_dir DISABLE_AUTOUPDATER=1 $claude_bin $session_mode_flag --permission-mode bypassPermissions --model $session_model --effort $session_effort 'Pipeline $label — olvasd el es kovesd pontosan a promptot ebbol a fajlbol: $prompt_file'" \
      "$session_log" "$signal_file" "$timeout_s" "$label" 1 \
      && [ -f "$signal_file" ]; then
      return 0
    fi

    if ! grep -qEi "$CLAUDE_LIMIT_PATTERN" "$session_log" 2>/dev/null \
      && ! claude_unavailable_until >/dev/null; then
      return 1   # nem kvóta: valódi hiba, ne égessük rá a Codex-keretet
    fi
    # A zárlat a Claude 5 órás ablakához igazodik; a pontos reset-időt nem
    # parse-oljuk (formátumfüggő lenne), a felső becslés biztonságos: a lánc
    # addig is halad, csak a másik motoron.
    printf '%s\n' "$(( $(date +%s) + claude_block_seconds ))" > "$claude_block_file"
    log "KVÓTA: a Claude-session limitre futott — átadás a $fallback_label motornak"
    notify "🔁 motorváltás: $label" "a Claude-kvóta kimerült — a $fallback_label veszi át" high
  fi

  if [ "$fallback_engine" = "none" ]; then
    log "nincs engedélyezett fallback motor (PIPELINE_FALLBACK_ENGINE=none) — a lánc áll"
    return 1
  fi
  command -v "$codex_bin" >/dev/null || { log "nincs $codex_bin CLI — a fallback nem indítható"; return 1; }

  codex_prompt=$(codex_prompt_file "$prompt_file")
  run_tmux_session "${tmux_session}-fallback" \
    "CODEX_HOME=$codex_home $codex_bin exec$orch_model_args -C $repo_root -s danger-full-access \"\$(cat $codex_prompt)\" < /dev/null" \
    "${session_log%.log}-fallback.log" "$signal_file" "$timeout_s" "$label ($orch_codex_label)" 0 \
    "$CODEX_PROCESS_COMM_PATTERN"
}

# --- Önjavítás (ADR 0112) --------------------------------------------------
# A mérce ujjlenyomata. Az önjavító kör NÖVELHETI a tesztek számát, de nem
# csökkentheti, és a gate-artefaktumokhoz nem nyúlhat. Ha mégis: nem oldjuk fel
# a láncot magunktól — ez az EGYETLEN pont, ahol ember dönt (docs/LESSONS.md,
# „a mércét is ellenőrizd").
gate_test_count() { git -C "$repo_root" ls-files -- test tools/tests | wc -l | tr -d ' '; }
gate_artifact_hashes() {
  local path
  for path in tools/round-gate.sh .github/workflows/build-apk.yml .github/workflows/router-ci.yml; do
    printf '%s:%s ' "$path" "$(git -C "$repo_root" rev-parse "HEAD:$path" 2>/dev/null || echo hiányzik)"
  done
}

# H-GATEGUARD false-positive fix (E03-R05, mért gyökérok): a heal branch neve
# determinisztikus (`heal/{{ROUND}}-{{HALT_CODE}}-{{ATTEMPT}}`, lásd
# docs/execution/pipeline-selfheal-prompt.md), ezért a heal SAJÁT diffje
# közvetlenül lekérdezhető a hozzá tartozó, squash-merge-elt PR-en keresztül —
# ahelyett, hogy a teljes main-t hasonlítanánk össze két időpontban. Az utóbbi
# hamis pozitívat ad, ha a heal FUTÁSA ALATT egy független, jogos commit
# (pl. egy másik ADR bevezetése) landol main-re és éppen egy őrzött útvonalat
# érint — pontosan ez történt: 8715773 (ADR 0115) a heal 07:50–08:08 közötti
# futása KÖZBEN módosította a router-ci.yml-t, a heal saját PR-je (#61) viszont
# egyáltalán nem nyúlt hozzá.
heal_pr_number() {   # $1=heal branch → a hozzá tartozó, MERGE-ELT PR száma (üres, ha nincs)
  gh pr list --search "head:$1" --state merged --json number --jq '.[0].number // empty' 2>/dev/null
}

heal_pr_gate_violation() {   # $1=PR szám → kiírja az okot és 0-val tér vissza, ha a heal SAJÁT diffje gyengítette a mércét; 1, ha nem (vagy nem eldönthető)
  local pr="$1" merge_sha base_sha files deleted
  merge_sha=$(gh pr view "$pr" --json mergeCommit --jq '.mergeCommit.oid // empty' 2>/dev/null)
  [ -n "$merge_sha" ] || return 1
  base_sha="${merge_sha}^"
  git -C "$repo_root" rev-parse "$base_sha" >/dev/null 2>&1 || return 1
  files=$(git -C "$repo_root" diff --name-only "$base_sha" "$merge_sha" -- \
    tools/round-gate.sh .github/workflows/build-apk.yml .github/workflows/router-ci.yml 2>/dev/null)
  if [ -n "$files" ]; then
    printf 'a heal saját PR-je (#%s) gate-artefaktumot módosított: %s' \
      "$pr" "$(printf '%s' "$files" | tr '\n' ',' | sed 's/,$//')"
    return 0
  fi
  deleted=$(git -C "$repo_root" diff --name-status "$base_sha" "$merge_sha" -- test tools/tests 2>/dev/null \
    | grep -c '^D')
  if [ "${deleted:-0}" -gt 0 ]; then
    printf 'a heal saját PR-je (#%s) %s teszt-fájlt törölt' "$pr" "$deleted"
    return 0
  fi
  return 1
}

heal_attempts() {   # $1=kör $2=halt-kód → az eddigi kísérletek száma
  local key="$1|$2" line
  [ -f "$heal_count_file" ] || { echo 0; return; }
  line=$(cat "$heal_count_file")
  case "$line" in
    "$key|"*) printf '%s\n' "${line##*|}" ;;
    *) echo 0 ;;
  esac
}

# --- Terra napi-budget felfüggesztés (E03-R08 H6 önjavítás, 2026-08-02) ----
# MÉRT történeti gyökérok: pozitív Terra napi automatikus budget mellett
# (.ai/router.toml max_automatic_terra_calls_per_utc_day > 0) a keret kizárólag
# UTC nap-váltáskor nyílik meg újra — egy 5 percenkénti cron-retry ugyanazt a
# falat éri újra. A 0 érték 2026-08-02 óta korlátlant jelent; a helper ezért
# a korábbi véges policyből maradt holdot is biztonságosan eltávolítja. A hold
# kör-specifikus és időkorlátos: a
# `terra-status` CLI ugyanazt a `daily_terra_count`-ot kérdezi, amit
# `reserve_terra` is a döntéséhez használ (state.py) — nincs duplikált szabály.
terra_hold_file() { printf '%s/terra-budget-hold' "$state_dir"; }

terra_status_json() {   # stdout: a terra-status JSON, vagy üres, ha nem lekérdezhető
  python3 "$repo_root/tools/model-router.py" --config "$repo_root/.ai/router.toml" terra-status 2>/dev/null
}

terra_daily_budget_is_unlimited() {
  local status_json
  status_json=$(terra_status_json) || return 1
  [ -n "$status_json" ] || return 1
  printf '%s' "$status_json" | python3 -c \
    'import json,sys; raise SystemExit(0 if json.load(sys.stdin).get("unlimited") is True else 1)' \
    2>/dev/null
}

terra_hold_if_exhausted() {   # $1=kör — hold-fájlt ír, ha a napi Terra-budget MOST kimerült
  local round="$1" status_json exhausted next_epoch
  # Módosítás (ADR 0112 önjavító kör, 2026-08-02, E03-R08 H6 2. javítás):
  # `terra-status` a dokumentált viselkedése szerint (HANDOFF.md) NEMNULLA
  # exit-tel tér vissza pontosan akkor, amikor exhausted=true — a korábbi
  # `|| return 0` ezt az esetet is hibaként kezelte, ezért a hold-fájl SOHA
  # nem íródott ki (4 egymást követő H6 halt ugyanazon a napon, mielőtt ezt
  # mérve megtalálták). A tényleges lekérdezési hiba jele az ÜRES kimenet,
  # amit az alábbi sor már önmagában is véd.
  status_json=$(terra_status_json)
  [ -n "$status_json" ] || return 0
  exhausted=$(printf '%s' "$status_json" | python3 -c "import json,sys; print(json.load(sys.stdin).get('exhausted'))" 2>/dev/null)
  [ "$exhausted" = "True" ] || return 0
  next_epoch=$(printf '%s' "$status_json" | python3 -c "import json,sys; print(json.load(sys.stdin).get('next_reset_epoch'))" 2>/dev/null)
  case "$next_epoch" in ''|*[!0-9]*) return 0 ;; esac
  printf 'round=%s\nhold_until=%s\n' "$round" "$next_epoch" > "$(terra_hold_file)"
  log "Terra napi automatikus budget kimerült — $round felfüggesztve $(date -Is -d "@$next_epoch")-ig (a firing-ok addig session és önjavítási kísérlet nélkül kilépnek)"
}

terra_clear_stale_halt_for() {   # $1=kör — ha a HALTED fájl UGYANERRE a körre és Terra napi-budget kimerülésre hivatkozik (H6), ÉS a napi budget MOST már korlátlan, archiválja a HALTED-et, hogy a következő firing a KÖRT próbálja újra, ne egy újabb önjavító sessiont indítson egy már megszűnt okra
  # Módosítás (ADR 0112 önjavító kör, 2026-08-02, E03-R08 H6 7. előfordulás):
  # a hold-fájl törlése (`terra_hold_active_for`) önmagában NEM ELÉG — a
  # HALT-fájlt egy KORÁBBI firing írta ki (`handle_round_halt`, a HALT
  # ELSŐ észlelésekor), és a driver 2. szakasza (`[ -f "$halt_file" ]`)
  # attól teljesen függetlenül dönt, hogy létezik-e még hold-fájl. MÉRT
  # eset (élesben, ebben a repóban): a napi Terra-korlát eltávolítása
  # (PR #72) utáni ELSŐ firing helyesen törölte az akkor még élő
  # `terra-budget-hold` fájlt (a hold-fájl ezután nem is létezik többé) —
  # de a stale HALTED-et (a MÉG korlátozott policy alatt kiírva) ettől
  # függetlenül otthagyta, és a driver egy 7. valódi heal-sessiont
  # indított rá. Ezért ez a függvény ÖNÁLLÓAN, a hold-fájl állapotától
  # FÜGGETLENÜL kérdezi le a policy-t — nem feltételezi, hogy a hívó már
  # megerősítette a korlátlan állapotot.
  local round="$1" stamp halt_round halt_code halt_summary
  [ -f "$halt_file" ] || return 0
  halt_round=$(grep -m1 '^round=' "$halt_file" | cut -d= -f2-)
  [ "$halt_round" = "$round" ] || return 0
  halt_code=$(grep -m1 '^halt=' "$halt_file" | cut -d= -f2-)
  [ "$halt_code" = "H6" ] || return 0
  halt_summary=$(grep -m1 '^summary=' "$halt_file" | cut -d= -f2-)
  case "$halt_summary" in
    *"Terra"*"budget"*) : ;;
    *) return 0 ;;
  esac
  terra_daily_budget_is_unlimited || return 0
  stamp=$(date +%Y%m%dT%H%M%S)
  mv "$halt_file" "$state_dir/healed-$round-$stamp.txt"
  rm -f "$heal_count_file"
  log "a HALTED jelzés elavult volt (a Terra napi-korlát megszűnt, miközben a HALT rá hivatkozott) — törölve, a(z) $round kör önjavítás nélkül újra sorra kerül"
}

terra_hold_active_for() {   # $1=kör → 0 ha AKTÍV hold van rá, 1 egyébként (lejárt/nincs/másik kör → törli a lejárt/idegen fájlt)
  local round="$1" hold_file hold_round hold_until
  hold_file=$(terra_hold_file)
  [ -f "$hold_file" ] || return 1
  hold_round=$(grep -m1 '^round=' "$hold_file" | cut -d= -f2-)
  hold_until=$(grep -m1 '^hold_until=' "$hold_file" | cut -d= -f2-)
  case "$hold_until" in ''|*[!0-9]*) rm -f "$hold_file"; return 1 ;; esac
  if [ "$hold_round" = "$round" ] && [ "$(date +%s)" -lt "$hold_until" ]; then
    if terra_daily_budget_is_unlimited; then
      if ! rm -f "$hold_file"; then
        log "elavult Terra-hold nem törölhető — biztonságosan aktívnak kezeljük"
        return 0
      fi
      log "Terra napi automatikus budget korlátlan — az elavult hold törölve ($round)"
      return 1
    fi
    log "Terra napi budget felfüggesztés aktív ($round, $(date -Is -d "@$hold_until")-ig) — a firing kihagyva, nincs session, nincs önjavítási kísérlet"
    return 0
  fi
  rm -f "$hold_file"
  return 1
}

# --- Codex CLI usage-limit felfüggesztés (E05-R15 H6 önjavítás, 2026-08-07) -
# MÉRT gyökérok: a `terra_hold_if_exhausted` fent a ROUTER saját belső napi
# hívás-számlálóját kérdezi le (`terra-status`, `.ai/router.toml`
# `max_automatic_terra_calls_per_utc_day`) — ez teljesen más réteg, mint a
# Codex CLI ALATT futó fiók (bármelyik motor-profil, ADR 0140) saját, tényleges
# upstream usage-limitje. Az E05-R15 fix-round-2 ténylegesen ebbe futott bele
# (`ERROR: You've hit your usage limit... try again at Aug 8th, 2026 7:32 AM`,
# 3x azonos szöveg, .pipeline/HALTED, 2026-08-07T16:46:20Z), és a halt
# summary-je NEM illeszkedik a `*Terra*budget*` mintára (nincs benne a
# "budget" szó) — mérve:
#   case "Codex/Terra (gpt-5.6-terra) quota exhausted..." in *Terra*budget*)
#   → NEM illeszkedik.
# Enélkül egy sima `outcome=retry` UTÁN a lánc a KÖVETKEZŐ 5 perces firingen
# azonnal újra a kimerült falnak futna (a tényleges reset csak ~15 óra múlva
# jön), és 3 önjavító kísérlet ~15-20 percen belül elfogyna — miközben a
# tényleges ok magától megszűnik. A szöveg maga adja a reset-időt, ezért nincs
# szükség élő API-ra: a Codex CLI hibaszövegéből (halt- VAGY heal-summary)
# regex-szel vontuk ki.
codex_usage_limit_hold_file() { printf '%s/codex-usage-limit-hold' "$state_dir"; }

codex_usage_limit_reset_epoch_from_text() {   # $1=szöveg → epoch stdoutra, 1-es kilépés, ha nincs illeszkedő minta
  local text="$1" phrase
  phrase=$(printf '%s' "$text" | grep -oE \
    'try again at [A-Za-z]+ [0-9]{1,2}(st|nd|rd|th)?, [0-9]{4} [0-9]{1,2}:[0-9]{2} ?[AP]M' | head -1)
  [ -n "$phrase" ] || return 1
  phrase=${phrase#try again at }
  # A napi sorszám-utótagot (st/nd/rd/th) a GNU `date -d` nem érti — leválasztjuk.
  phrase=$(printf '%s' "$phrase" | sed -E 's/([0-9]+)(st|nd|rd|th)/\1/')
  # A Codex CLI szövege nem ad időzónát; a box és a `.pipeline/HALTED`
  # `halted_at` mezője is UTC (mérve), ezért a parszolást EXPLICIT UTC-re
  # kényszerítjük — nem az ambiens $TZ-re (más futtatókörnyezet, pl. a CI
  # runner rendszer-időzónája eltolná a hold_until-t).
  TZ=UTC date -d "$phrase" +%s 2>/dev/null
}

codex_usage_limit_hold_if_detected() {   # $1=kör $2=szöveg (halt- vagy heal-summary)
  local round="$1" text="$2" epoch
  epoch=$(codex_usage_limit_reset_epoch_from_text "$text") || return 0
  [ -n "$epoch" ] || return 0
  printf 'round=%s\nhold_until=%s\n' "$round" "$epoch" > "$(codex_usage_limit_hold_file)"
  log "Codex CLI usage-limit kimerült — $round felfüggesztve $(date -Is -d "@$epoch")-ig (a firing-ok addig session és önjavítási kísérlet nélkül kilépnek)"
}

codex_usage_limit_hold_active_for() {   # $1=kör → 0 ha AKTÍV hold van rá, 1 egyébként (lejárt/nincs/másik kör → törli a lejárt/idegen fájlt)
  local round="$1" hold_file hold_round hold_until
  hold_file=$(codex_usage_limit_hold_file)
  [ -f "$hold_file" ] || return 1
  hold_round=$(grep -m1 '^round=' "$hold_file" | cut -d= -f2-)
  hold_until=$(grep -m1 '^hold_until=' "$hold_file" | cut -d= -f2-)
  case "$hold_until" in ''|*[!0-9]*) rm -f "$hold_file"; return 1 ;; esac
  if [ "$hold_round" = "$round" ] && [ "$(date +%s)" -lt "$hold_until" ]; then
    log "Codex CLI usage-limit felfüggesztés aktív ($round, $(date -Is -d "@$hold_until")-ig) — a firing kihagyva, nincs session, nincs önjavítási kísérlet"
    return 0
  fi
  rm -f "$hold_file"
  return 1
}

# --- Claude-kvóta hold (E13-R16 mérés, 2026-08-25) -------------------------
# Ugyanaz a „csendes kihagyás" elv, mint a Terra napi-budgetnél és a Codex CLI
# usage-limitnél, a harmadik motor-rétegre: a Claude-előfizetés kimerülése
# KÜLSŐ, IDŐZÍTETT akadály — nincs mit javítani a repóban. A korábbi
# viselkedés (H-NOSIGNAL → önjavító kör → megint kvótafal → lánc-HALT kézi
# `--resume`-ig) a kísérletkeretet és a wall-clockot is elégette.
#
# A reset-időt a banner adja (`resets 8am (UTC)`), a parszolás a meglévő
# `claude_session_reset_epoch`-kal történik. HETI limitnél ez alulbecsülhet (a
# függvény napon belül/holnapra kerekít) — ez SZÁNDÉKOS és önjavító: a hold
# lejártakor a lánc újra próbálkozik, és ha a keret még zárva van, az első
# session újra kiírja a holdot. Egy napi egy elveszett session-indítás az ára,
# szemben a mért 3 önjavító kísérlettel + 11 órás álló lánccal.
claude_quota_hold_file() { printf '%s/claude-quota-hold' "$state_dir"; }

claude_quota_hold_if_detected() {   # $1=kör $2=session-napló → hold, ha a naplóban kvóta-nyom van
  local round="$1" logfile="$2" epoch
  [ -n "$logfile" ] && [ -r "$logfile" ] || return 1
  grep -qaEi "$CLAUDE_LIMIT_PATTERN" "$logfile" 2>/dev/null || return 1
  epoch=$(claude_session_reset_epoch "$logfile" 2>/dev/null || true)
  case "$epoch" in ''|*[!0-9]*) epoch=$(( $(date +%s) + claude_block_seconds )) ;; esac
  printf 'round=%s\nhold_until=%s\n' "$round" "$epoch" > "$(claude_quota_hold_file)"
  printf '%s\n' "$epoch" > "$claude_block_file"
  log "Claude-kvóta kimerült — $round felfüggesztve $(date -Is -d "@$epoch")-ig (a firing-ok addig session és önjavítási kísérlet nélkül kilépnek)"
  return 0
}

claude_quota_hold_active_for() {   # $1=kör → 0 ha AKTÍV hold van rá, 1 egyébként (lejárt/nincs/másik kör → törli a lejárt/idegen fájlt)
  local round="$1" hold_file hold_round hold_until
  hold_file=$(claude_quota_hold_file)
  [ -f "$hold_file" ] || return 1
  hold_round=$(grep -m1 '^round=' "$hold_file" | cut -d= -f2-)
  hold_until=$(grep -m1 '^hold_until=' "$hold_file" | cut -d= -f2-)
  case "$hold_until" in ''|*[!0-9]*) rm -f "$hold_file"; return 1 ;; esac
  if [ "$hold_round" = "$round" ] && [ "$(date +%s)" -lt "$hold_until" ]; then
    log "Claude-kvóta felfüggesztés aktív ($round, $(date -Is -d "@$hold_until")-ig) — a firing kihagyva, nincs session, nincs önjavítási kísérlet"
    return 0
  fi
  rm -f "$hold_file"
  return 1
}

handle_round_halt() {   # $1=kör $2=status-fájl $3=session-napló — a HALT ELSŐ észlelésekor: halt_file írás + Terra-hold determinisztikus ellenőrzés
  # Módosítás (ADR 0112 önjavító kör, 2026-08-02, E03-R08 H6 5. előfordulás,
  # lásd docs/LESSONS.md L63 folytatása): korábban a Terra napi-hold
  # KIZÁRÓLAG az önjavítás retry-ágából íródott ki (attempt_selfheal, az
  # LLM-jelentés szövegére string-matchelve). Ha egy heal-kör egy MÁSIK
  # gyökérokot javított (pl. magát a hold-író függvényt, PR #70) —
  # `outcome=fixed`, nem `retry` —, ez az ág soha nem futott le, és a
  # következő firing UGYANAZT a naptár-korlátozott Terra-falat érte el
  # újra (4 halt egy napon, 14:26–16:38 UTC). A hívás itt, a HALT ELSŐ
  # észlelésekor — mielőtt bármilyen self-heal session elindulna —
  # determinisztikus: az élő terra-status-t kérdezi le, nem az LLM
  # jelentésének szövegére épül.
  local round="$1" status_file="$2" session_log="$3" halt_code summary
  halt_code=$(grep -m1 '^halt=' "$status_file" | cut -d= -f2-)
  summary=$(grep -m1 '^summary=' "$status_file" | cut -d= -f2-)
  {
    cat "$status_file"
    echo "session_log=$session_log"
    echo "halted_at=$(date -Is)"
  } > "$halt_file"
  terra_hold_if_exhausted "$round"
  codex_usage_limit_hold_if_detected "$round" "$summary"
  claude_quota_hold_if_detected "$round" "$session_log" || true
  log "HALT ($halt_code) a(z) $round körön — $summary"
  notify "⛔ HALT ($halt_code): $round" "$summary — az önjavító kör a következő firingen indul" high
  log "az önjavítás (ADR 0112) a következő cron-firingen indul; kikapcsolva: PIPELINE_SELFHEAL=0"
}


# --- H-GATEGUARD: KÖR-szintű hold, nem LÁNC-szintű megállás (ADR 0321) -----
# MÉRVE 2026-08-19 (E99-R17, három egymást követő halt 05:31 / 09:56 / 10:38):
# a `H-GATEGUARD` az ADR 0112 egyetlen emberi határa, ezért az önjavítás
# helyesen nem nyúl hozzá — a HALTED jelzés viszont GLOBÁLIS, így EGYETLEN
# gate-érintő kör a sor MIND a 37 nyitott körét megállította, köztük a tőle
# teljesen független E07/E08 termék-munkát. A mérce változatlan: a kör NEM
# fut le, ember dönt róla. Csak a hatóköre szűkül a saját sorára.
#
# A `gateguard_origin=selfheal` mezőt az őrszem-ág írja (lásd attempt_selfheal):
# ott a halt azt jelenti, hogy a MAIN-en már állhat a mércét gyengítő commit —
# az továbbra is lánc-szintű megállás, mert a következő kör mércéje is romlott.
queue_hold_round() {   # $1=kör $2=indoklás → 0 ha a sor 'hold'-ra állt ÉS fel van tolva
  local round="$1" reason="$2"
  [ -f "$queue_file" ] || { log "sor-fájl hiányzik — nem állítható hold-ra: $round"; return 1; }
  grep -qP "^$round\t.*\tpending$" "$queue_file" || {
    log "a(z) $round sora nem 'pending' — hold-ra állítás kihagyva"
    return 1
  }
  if [ -z "${PIPELINE_STATE_DIR:-}" ]; then
    # Éles ág: a sor-fájl a repóban van, a változást commitolni KELL, mert a
    # következő firing „piszkos munkafa" őre különben megállítja a láncot.
    [ "$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" = "main" ] || {
      log "a munkafa nem a main-en van — a(z) $round hold-ra állítása kimarad (marad a lánc-szintű halt)"
      return 1
    }
    [ -z "$(git status --porcelain)" ] || {
      log "piszkos munkafa — a(z) $round hold-ra állítása kimarad (marad a lánc-szintű halt)"
      return 1
    }
    git fetch -q origin main && git reset -q --hard origin/main || {
      log "a main szinkronizálása nem sikerült — a(z) $round hold-ra állítása kimarad"
      return 1
    }
  fi
  sed -i "s|^\($round\t.*\t\)pending$|\1hold|" "$queue_file"
  grep -qP "^$round\t.*\thold$" "$queue_file" || {
    log "a(z) $round sorát nem sikerült hold-ra írni"
    return 1
  }
  [ -n "${PIPELINE_STATE_DIR:-}" ] && return 0
  git add "$queue_file" || return 1
  git commit -q -m "chore(pipeline): $round hold — $reason (ADR 0321)" || {
    git checkout -q -- "$queue_file" 2>/dev/null || true
    return 1
  }
  if ! git push -q origin main; then
    # A leggyakoribb ok: az origin/main közben elmozdult. Egy rebase után
    # újrapróbáljuk; ha az sem megy, VISSZAVONJUK a lokális commitot —
    # különben a következő firing a „lokális main eltér" ágon állna meg.
    if ! { git fetch -q origin main && git rebase -q origin/main && git push -q origin main; }; then
      log "a hold-commit push-a nem ment át — visszavonva, marad a lánc-szintű halt ($round)"
      git rebase --abort >/dev/null 2>&1 || true
      git reset -q --hard origin/main
      return 1
    fi
  fi
  return 0
}

gateguard_ledger_append() {   # $1=kör $2=halt-kód $3=összefoglaló
  printf '%s\t%s\t%s\t%s\n' "$(date -Is)" "$1" "$2" "$3" >> "$state_dir/gateguard-holds.tsv"
}

gateguard_hold_halted_round() {   # 0 = a haltot kör-szintű hold váltotta ki és el van intézve; 1 = maradjon a lánc-szintű halt
  local round halt_code summary origin archive
  [ "${PIPELINE_GATEGUARD_AUTOHOLD:-1}" = "1" ] || return 1
  [ -f "$halt_file" ] || return 1
  halt_code=$(grep -m1 '^halt=' "$halt_file" | cut -d= -f2-)
  summary=$(grep -m1 '^summary=' "$halt_file" | cut -d= -f2-)
  origin=$(grep -m1 '^gateguard_origin=' "$halt_file" | cut -d= -f2-)
  [ "$origin" = "selfheal" ] && return 1
  case "$halt_code" in
    H-GATEGUARD) ;;
    *) case "$summary" in H-GATEGUARD*) ;; *) return 1 ;; esac ;;
  esac
  round=$(grep -m1 '^round=' "$halt_file" | cut -d= -f2-)
  [ -n "$round" ] || return 1
  queue_hold_round "$round" "H-GATEGUARD" || return 1
  archive="$state_dir/gateguard-hold-$round-$(date +%Y%m%dT%H%M%S).txt"
  {
    cat "$halt_file"
    echo "resolution=queue-hold"
    echo "held_at=$(date -Is)"
  } > "$archive"
  rm -f "$halt_file"
  gateguard_ledger_append "$round" "$halt_code" "$summary"
  log "H-GATEGUARD → HOLD: a(z) $round sora 'hold' (emberi döntés kell hozzá), a lánc a többi körrel MEGY TOVÁBB — archívum: $archive"
  notify "⏸️ H-GATEGUARD → hold: $round" "a kör emberi gate-döntésre vár; a lánc a következő körrel folytatódik" high
  return 0
}

# Kimenet: 0 = a halt feloldva, mehet tovább a lánc; 3 = áll, ember kell.
attempt_selfheal() {
  local halt_round halt_code attempts stamp prompt_file heal_log
  local tests_before hashes_before tests_after hashes_after outcome summary
  local heal_branch pr_number violation round_engine heal_engine engine_note
  local stall_hours
  # A heal-ülés orchestrátora KÖRNYEZETI döntés (lásd lentebb a Sol-pint), és
  # csak erre a hívásra érvényes: bash dinamikus hatókör miatt a `local` a
  # meghívott run_orchestrator_session-ben is látszik, a függvény visszatérése
  # után viszont a globális érték áll vissza.
  local orchestrator_preference="$orchestrator_preference"

  halt_round=$(grep -m1 '^round=' "$halt_file" | cut -d= -f2-)
  halt_code=$(grep -m1 '^halt=' "$halt_file" | cut -d= -f2-)
  [ -n "$halt_round" ] || halt_round="ismeretlen"
  [ -n "$halt_code" ] || halt_code="H-UNKNOWN"

  if [ "$selfheal_enabled" != "1" ]; then
    log "önjavítás kikapcsolva (PIPELINE_SELFHEAL=0) — a feloldás emberi: tools/pipeline-status.sh --resume"
    return 3
  fi

  # MÉRVE ÉLESBEN 2026-08-16 (E07-R09 H-NOSIGNAL önjavítás, 1. kísérlet
  # közben): az attempt_selfheal() idáig SOSE regisztrálta magát az
  # inflight_dir-ben, szemben a normál kör-dispatch-csal, amely
  # `inflight_add "$round" "$brief"`-t hív a session indítása előtt (lentebb
  # a §4 törzsében) — l. tools/tests/test_round_pipeline_queue_pending_pr_guard.py
  # fejléce ugyanerről a regiszterről. A HALTED fájl addig megmarad, amíg EGY
  # önjavító session le nem zárja; eközben MINDEN cron-firing (itt 5
  # percenként) újra azt látja: „HALTED jelen van, van szabad slot", és
  # újabb önjavítási kísérletet indít, akkor is, ha az előző MÉG FUT. Élesben
  # mérve: `heal-E07-R09-1` 02:00:03-kor indult (ez a session), a driver
  # semmit nem tudott róla, és `heal-E07-R09-2` 02:05:02-kor — ekkor mindkét
  # slot (PIPELINE_SLOTS=2) egyszerre futtatott egy-egy Claude-orchestrátort
  # UGYANARRA a haltra, mindkettő a KÖZÖS `$heal_status_file`-t írta volna a
  # végén (`run_orchestrator_session` `rm -f "$signal_file"`-lel INDUL, tehát
  # a később induló törli a korábban induló jelzését is, ha az közben ír), és
  # a puszta párhuzamos indulás — nem valódi kudarc — fogyasztott el egy
  # kísérletet a $selfheal_max (3) büdzséből (l. `selfheal.count` 2-nél állt,
  # mielőtt bármelyik session befejeződött volna).
  if inflight_rounds | grep -qFx "$halt_round"; then
    log "önjavítás már fut ehhez a körhöz ($halt_round) — ez a firing kihagyja (nincs párhuzamos önjavító session, nem számít bele a kísérletbe)"
    return 3
  fi

  # Nem önjavítható haltok (ADR 0138). Az ADR 0112 egyetlen emberi határa a
  # MÉRCE gyengítése; ide tartozik minden olyan ok, amit az önjavító session
  # KÖRBEN oldana fel — a H-INDEP-et például kvótazárlat alatt maga a Terra
  # javítaná, holott épp az a baj, hogy a Terra vizsgálná a saját munkáját.
  case "$halt_code" in
    H-GATEGUARD | H-INDEP)
      log "a(z) $halt_code önjavítása tilos — emberi döntés kell (tools/pipeline-status.sh --resume)"
      notify "⛔ $halt_code: $halt_round" "emberi döntés kell, az önjavítás nem indul" high
      return 3
      ;;
  esac
  if [ ! -f "$heal_template" ]; then
    log "hiányzik az önjavító prompt-sablon ($heal_template) — a lánc áll"
    return 3
  fi

  attempts=$(heal_attempts "$halt_round" "$halt_code")
  if [ "$attempts" -ge "$selfheal_max" ]; then
    log "az önjavítás KIMERÜLT ($attempts/$selfheal_max) — $halt_round / $halt_code"
    if halt_reminder_due "$halt_round" "$halt_code"; then
      stall_hours=$(halt_stall_hours) || stall_hours="?"
      notify "🛑 önjavítás kimerült: $halt_round" \
        "$halt_code — $selfheal_max kísérlet után is áll, ${stall_hours} órája: tools/pipeline-status.sh --resume" \
        "$(halt_reminder_priority)"
      record_halt_reminder "$halt_round" "$halt_code"
    fi
    return 3
  fi
  attempts=$(( attempts + 1 ))
  printf '%s|%s|%s\n' "$halt_round" "$halt_code" "$attempts" > "$heal_count_file"

  # A self-heal dispatch nem a halt-olt kör implementerét kapja, hanem egy
  # RÖGZÍTETT identitást (brief §0.0). Az utolsó próbálkozás ebből választ
  # eltérő, más modellű alternatívát a nyilvántartásból.
  #
  # user-döntés 2026-08-20 (kiterjesztés: „mind a két sloton a Sol
  # orchestrátor és a Terra implementer dolgozzon"): az önjavító kör IS
  # slotot foglal (`inflight_add` lentebb), tehát a Sol-pin alatt ez a
  # munkadarab sem mehet a Claude-keretből — a heal-ülést a Sol vezényli
  # (`gpt-5.6-sol`, a Terráéval közös CODEX_HOME/auth, explicit `-m`), a
  # rögzített identitás pedig a nyilvántartás `sol` sora, hogy az utolsó
  # kísérlet MÉRHETŐEN más modellre válthasson (ADR 0307 §2 lever).
  # Pin nélkül (alternate | claude | terra rotáció) minden BIT-RE a régi,
  # kvóta-tudatos Claude→Terra úton marad.
  if [ "$orch_rotation" = "sol" ] && [ "$fallback_engine" != "none" ]; then
    orchestrator_preference=sol
    round_engine="sol"
  else
    orchestrator_preference=claude
    round_engine="sonnet-impl"
  fi
  heal_engine=$(heal_engine_for_attempt "$halt_round" "$halt_code" "$attempts" "$round_engine")
  if [ "$attempts" -eq "$selfheal_max" ]; then
    if [ "$heal_engine" != "$round_engine" ]; then
      log "ÖNJAVÍTÓ MOTORVÁLTÁS: $halt_round $round_engine → $heal_engine (utolsó kísérlet)"
      notify "🔁 ÖNJAVÍTÓ MOTORVÁLTÁS: $halt_round" \
        "$round_engine → $heal_engine (utolsó kísérlet)" high
      engine_note="**MÁS MOTOR futtatja ezt az utolsó kísérletet:** $round_engine helyett $heal_engine. Olvasd el az előző két .pipeline/heal-*.log naplót: ezek bemenetek a diagnózishoz, ne ismételd meg változtatás nélkül ugyanazt a munkát."
    else
      log "ÖNJAVÍTÓ MOTORVÁLTÁS NINCS: $halt_round / $halt_code — nincs elérhető, más modellű támogatott motor; a mai $round_engine viselkedés marad"
      engine_note="Az utolsó kísérlethez nincs elérhető, más modellű támogatott motor, ezért a mai $round_engine viselkedés marad."
    fi
  else
    engine_note="Ez még nem az utolsó önjavító kísérlet; a rögzített $round_engine motor fut."
  fi

  # A mérce állapota a javítás ELŐTT, a jelenlegi main-en.
  git fetch -q origin main 2>/dev/null || true
  tests_before=$(gate_test_count)
  hashes_before=$(gate_artifact_hashes)

  stamp=$(date +%Y%m%dT%H%M%S)
  prompt_file="$state_dir/heal-prompt-$halt_round-$stamp.md"
  heal_log="$state_dir/heal-$halt_round-$stamp.log"
  sed -e "s|{{ROUND}}|$halt_round|g" \
      -e "s|{{HALT_CODE}}|$halt_code|g" \
      -e "s|{{ATTEMPT}}|$attempts|g" \
      -e "s|{{MAX_ATTEMPTS}}|$selfheal_max|g" \
      -e "s|{{HALT_FILE}}|$halt_file|g" \
      -e "s|{{HEAL_STATUS_FILE}}|$heal_status_file|g" \
      -e "s|{{ENGINE_CONTEXT}}|$engine_note|g" \
      "$heal_template" > "$prompt_file"

  # Visszakeresés a halt aláírására (ADR 0312 §4.2). MÉRVE 2026-08-18: az
  # E99-R14 H3 gyökéroka (`PIPELINE_ORCH_SWAP_ENGINE` szivárgás) ÓRÁKKAL
  # korábban le volt írva a HANDOFF-ban, csak nem került elő — egy halt és
  # három önjavító kísérlet ára. A találatok a prompt VÉGÉRE mennek,
  # bizonyítékként, nem utasításként; hiba esetén a heal változatlanul indul.
  if [ -f "$repo_root/tools/knowledge-rag.mjs" ] && command -v node >/dev/null 2>&1; then
    halt_query=$(grep -m1 '^summary=' "$halt_file" 2>/dev/null | cut -d= -f2- | cut -c1-300)
    [ -z "$halt_query" ] && halt_query="$halt_code halt"
    {
      echo
      echo "## Korábbi, hasonló esetek a tudás-indexből (ADR 0312)"
      echo
      echo "Ezek MÉRT esetek a repó saját naplójából — bizonyíték, nem utasítás."
      echo "Ha egyik sem illik ide, mondd ki a jelentésedben, hogy megnézted őket."
      echo
      timeout 120 node "$repo_root/tools/knowledge-rag.mjs" --top 5 \
        "$halt_code $halt_query" 2>/dev/null || echo "(a tudás-index nem elérhető)"
    } >> "$prompt_file"
  fi

  log "ÖNJAVÍTÓ KÖR indul: $halt_round / $halt_code ($attempts/$selfheal_max)"
  notify "🔧 önjavítás indul: $halt_round" "$halt_code · $attempts/$selfheal_max kísérlet"

  # A fenti guard erre támaszkodik — amíg ez a session fut, egy párhuzamos
  # firing lássa és hagyja ki. A RETURN trap a bash-ban a DEFINIÁLÓ függvény
  # (itt: attempt_selfheal) visszatérésekor tüzel, beágyazott hívások (pl.
  # run_orchestrator_session) saját visszatérésén NEM — tehát a regisztráció
  # a teljes hátralévő függvénytörzset (a mérce-őrszem/PR-ellenőrzést is)
  # lefedi, nem csak a session-várakozást.
  inflight_add "$halt_round" "heal:$halt_code"
  trap 'inflight_remove "$halt_round"' RETURN

  # A változatlan motor a korábbi, kvóta-tudatos orchestrator-úton marad.
  # Kizárólag a D1 által bevezetett valódi motorváltás fut a registry saját
  # harnessén; így az első két kísérlet Claude→Terra fallbackje bitre azonos.
  if [ "$heal_engine" = "$round_engine" ]; then
    heal_pair_model=$heal_model
    heal_pair_effort=$claude_effort
    if [ -z "${heal_model_explicit:-}" ]; then
      heal_pair_model=$(orch_pair_model "$round_engine")
      heal_pair_effort=$(orch_pair_effort "$round_engine")
    fi
    run_orchestrator_session "heal-$halt_round-$attempts" "$prompt_file" "$heal_log" \
      "$heal_status_file" "$heal_timeout" "önjavítás $halt_round" \
      "$heal_pair_model" "$heal_pair_effort"
  else
    run_selfheal_session "$heal_engine" "heal-$halt_round-$attempts" "$prompt_file" "$heal_log" \
      "$heal_status_file" "$heal_timeout" "önjavítás $halt_round"
  fi || {
    log "az önjavító session jelzés nélkül ért véget — a lánc áll"
    notify "⛔ önjavítás jelzés nélkül halt" "$halt_round / $halt_code — kivizsgálás kell" high
    return 3
  }

  outcome=$(grep -m1 '^outcome=' "$heal_status_file" | cut -d= -f2-)
  summary=$(grep -m1 '^summary=' "$heal_status_file" | cut -d= -f2-)

  case "$outcome" in
    fixed)
      : # lentebb: mérce-őrszem, majd feloldás
      ;;
    retry)
      # Külső, átmeneti akadály (kvóta, szolgáltatás-kiesés): nem volt mit
      # javítani a repóban. Feloldjuk a láncot, de a kísérletszámlálót MEGTARTJUK,
      # hogy egy tartós kiesés ne pörgesse a láncot a végtelenségig.
      mv "$halt_file" "$state_dir/healed-$halt_round-$stamp.txt"
      log "átmeneti akadály volt ($summary) — a lánc feloldva, a kör újra sorra kerül"
      notify "🔁 újrapróbálás: $halt_round" "$summary"
      case "$summary" in
        *"Terra daily budget is exhausted"* | *"Terra"*"budget"*)
          terra_hold_if_exhausted "$halt_round"
          ;;
      esac
      codex_usage_limit_hold_if_detected "$halt_round" "$summary"
      return 0
      ;;
    *)
      log "az önjavítás nem oldotta fel ($outcome) — $summary"
      notify "⛔ önjavítás sikertelen: $halt_round" "$outcome — $summary" high
      return 3
      ;;
  esac

  # A javítás után a main-t szinkronizáljuk, és MEGMÉRJÜK a mércét.
  git checkout -q main 2>/dev/null || true
  git fetch -q origin main && git reset -q --hard origin/main
  tests_after=$(gate_test_count)
  hashes_after=$(gate_artifact_hashes)

  # Az őrszem a heal SAJÁT diffjét vizsgálja (determinisztikus branch-név →
  # a hozzá tartozó merge-elt PR), NEM a teljes main előtte/utána állapotát —
  # az utóbbi hamis pozitívat adna egy, a heal futása KÖZBEN landolt, tőle
  # független commitra (mért eset: E03-R05 H6, lásd docs/LESSONS.md).
  heal_branch="heal/${halt_round}-${halt_code}-${attempts}"
  pr_number=$(heal_pr_number "$heal_branch")
  violation=""
  if [ -n "$pr_number" ]; then
    violation=$(heal_pr_gate_violation "$pr_number") || violation=""
  else
    log "GATEGUARD: nincs merge-elt PR a(z) $heal_branch branch-hez — a teljes main-ujjlenyomatra esünk vissza"
    if [ "$tests_after" -lt "$tests_before" ] || [ "$hashes_after" != "$hashes_before" ]; then
      violation="nem található a heal saját PR-je a determinisztikus branch-néven, és a teljes main-ujjlenyomat is változott (teszt-fájlok: $tests_before → $tests_after)"
    fi
  fi

  if [ -n "$violation" ]; then
    {
      echo "round=$halt_round"
      echo "halt=H-GATEGUARD"
      # Gépi megkülönböztetés (ADR 0321): ezt a haltot az ŐRSZEM írta, tehát a
      # mércét gyengítő commit MÁR a main-en állhat — a lánc egésze áll meg,
      # nem csak ez a kör. A kör-session által jelzett H-GATEGUARD (ott ez a
      # mező hiányzik) ezzel szemben csak a saját sorát tartja vissza.
      echo "gateguard_origin=selfheal"
      echo "summary=az önjavítás a MÉRCÉHEZ nyúlt — emberi jóváhagyás kell: $violation"
      echo "detail=eredeti halt: $halt_code · javítás: $summary · napló: $heal_log"
      echo "halted_at=$(date -Is)"
    } > "$halt_file"
    log "ŐRSZEM: az önjavítás gyengíthette a mércét — a lánc áll (H-GATEGUARD)"
    notify "⛔ H-GATEGUARD: $halt_round" "az önjavítás a gate-hez nyúlt — nézd át, mielőtt feloldod" high
    return 3
  fi

  mv "$halt_file" "$state_dir/healed-$halt_round-$stamp.txt"
  rm -f "$heal_count_file"
  log "ÖNJAVÍTÁS KÉSZ — a lánc feloldva: $summary"
  notify "✅ önjavítás kész: $halt_round" "$summary — a lánc megy tovább"
  return 0
}

# --- Reviewer-függetlenség (ADR 0138) -------------------------------------
# MÉRT tény 2026-08-05: az implementer (`codex exec`, `~/.codex`) és az
# orchestrátor-fallback (`~/.codex-terra`) UGYANAZ a `gpt-5.6-terra` modell.
# Claude-kvótazárlat alatt tehát a Terra review-zná a SAJÁT diffjét — ez az
# egyetlen pont, ahol a lánc független bizonyíték nélkül merge-elne
# (ADR 0055: egy ágens nem hagyhatja jóvá a saját munkáját; a starter-csomag
# SDD §2.2 is explicit nem-célként nevezi meg).
#
# A feloldás NEM halt: az ADR 0115 célja épp az volt, hogy a lánc ne
# szakadjon meg. Az implementert visszük át a MÁSIK motorra, így a reviewer
# (Terra) és az implementer (MiniMax) újra elválik. Ha nincs másik motor,
# H-INDEP halt — az önjavítása tiltott, mert körben oldaná fel.
#
# Kiírja: a feloldott motort, vagy `HALT_INDEP`-et.
#
# ADR 0222 kiterjesztés: a trigger már NEM csak a Claude-kvótazárlat, hanem
# minden Terra-vezényelt kör (a rotáció is odaad minden másodikat). A csere-
# motor alapból a `sonnet-impl` — így a szerepek cserélnek, nem gyengül a
# mezőny.
engine_registry_row() {   # $1=motor neve → a nyilvántartás sora
  [ -r "$engine_registry" ] || return 1
  grep -v '^[[:space:]]*#' "$engine_registry" | awk -F'\t' -v n="$1" '$1 == n {print; found=1; exit} END {exit !found}'
}

# 0, ha a motor az ELŐFIZETÉSES Claude-keretet fogyasztja (claude harness ÉS
# nincs saját API-kulcsa). A `minimax` is claude-harness, de saját kulccsal
# külső endpointra megy — annak a keretéhez a Claude-zárlatnak semmi köze.
engine_uses_claude_quota() {   # $1=motor neve
  local row
  row=$(engine_registry_row "$1") || return 1
  [ "$(printf '%s' "$row" | cut -f2)" = "claude" ] || return 1
  [ "$(printf '%s' "$row" | cut -f5)" = "-" ]
}

resolve_independent_engine() {   # $1=queue-motor [$2=orchestrátor]
  local queue_engine=${1:-} orchestrator=${2:-} claude_blocked=0
  [ -n "$orchestrator" ] || orchestrator=$(next_orchestrator)

  # Csak a Terra-MODELLT futtató implementer ütközik a Terra reviewerrel.
  # MÉRT hiba (2026-08-11): az eredeti feltétel csak a `codex` nevet nézte, az
  # ADR 0140 óta élő `.pipeline/engine-override=terra` mellett viszont a motor
  # neve `terra` — a függetlenség-védelem így NEM lépett volna kvótazárlat
  # alatt sem, pedig ugyanaz a gpt-5.6-terra modell mindkettő.
  case "$queue_engine" in codex|terra) ;; *) printf '%s\n' "$queue_engine"; return 0 ;; esac

  if [ "$fallback_engine" = "none" ] || [ "$orchestrator" != "terra" ]; then
    printf '%s\n' "$queue_engine"
    return 0
  fi

  claude_unavailable_until >/dev/null && claude_blocked=1
  claude_usage_block_until >/dev/null && claude_blocked=1

  if [ -n "$orch_swap_engine" ] && [ "$orch_swap_engine" != "$queue_engine" ] \
     && engine_registry_row "$orch_swap_engine" >/dev/null \
     && { [ "$claude_blocked" = "0" ] || ! engine_uses_claude_quota "$orch_swap_engine"; }; then
    printf '%s\n' "$orch_swap_engine"
    return 0
  fi
  if [ -n "${MINIMAX_API_KEY:-}" ] || [ -f "$HOME/.mmx/config.json" ]; then
    printf 'minimax\n'
  else
    printf 'HALT_INDEP\n'
  fi
}

# --- Folytatáskori függetlenség-revalidáció (ADR 0242 D2) ------------------
# MÉRT ok: `resolve_independent_engine` csak FRISS dispatchre old fel
# implementert — nem tud a körhöz már COMMITOLT implementerről. Ha a kör
# elhalt és újraindul, a régi (globális) rotáció a MÁSIK orchestrátort adta,
# miközben az ágon már egy adott motor commitolt — nincs független reviewer
# (E06-R23 H-INDEP, 4 óra 35 perc állásidő).
#
# Folytatáskor az implementer az ágról MÉRT tény (fix); a mozgatható szereplő
# az ORCHESTRÁTOR — ez a fordítottja a fenti resolve_independent_engine
# irányának (ami az implementert billenti).

# Kiírja, hogy egy adott kör-ágon commitolt implementer ÜTKÖZIK-e a megadott
# orchestrátorral (ugyanazt az identitást/kvótát fogyasztaná).
orchestrator_conflicts_with_implementer() {   # $1=orchestrátor(claude|terra|sol) $2=implementer motor
  local row
  case "$1" in
    # 2026-08-23 user-döntés: a claude-ág is MODELL-azonosságon mér, nem puszta
    # kvóta-azonosságon — ugyanazon a kulcson, ahogy a `sol` ág teszi a közös
    # Pro-előfizetés fölött. Indok: az orchestrátor Opus 5, az implementer
    # `sonnet-impl` (Sonnet 5) — más modell, tehát nem a saját diffjét
    # review-zi. A KÖZÖS Claude-előfizetés vállalt kockázat (a 85%-os fék,
    # PIPELINE_CLAUDE_SESSION_PCT_MAX, változatlanul él). Fail-closed marad:
    # ha valaki PIPELINE_MODEL=claude-sonnet-5-re állítja vissza az
    # orchestrátort, a `sonnet-impl` ismét ütközik.
    claude)
      engine_uses_claude_quota "$2" || return 1
      row=$(engine_registry_row "$2") || return 1
      # NEM a globális defaulthoz mérünk, hanem ahhoz a modellhez, amit ez a
      # kör TÉNYLEGESEN kapna (orch_pair_model — ugyanaz a feloldó, ami a
      # sessiont indítja). Fail-closed marad: ha a pár egy nap ugyanarra a
      # modellre mutatna, mint az implementer, ez ütközést jelent.
      [ "$(printf '%s' "$row" | cut -f4)" = "$(orch_pair_model "$2")" ]
      ;;
    # Csak a Terra-MODELLT (gpt-5.6-terra) futtató implementer ütközik a
    # Terra orchestrátorral/reviewerrel — ugyanaz a mérés, mint
    # resolve_independent_engine-ben (2026-08-11 mért rés: a `codex` név is
    # ide tartozik, nem csak a `terra`).
    terra) case "$2" in codex|terra) return 0 ;; *) return 1 ;; esac ;;
    # A Sol ugyanazon a modell-azonossági kulcson mér, mint a terra ág: a
    # Sol-MODELLT futtató implementer ütközik vele. A nyilvántartás `sol`
    # sora (2026-08-20, a heal-identitás miatt) pontosan ilyen — implementer-
    # nek választva tehát fail-closed `H-INDEP`; a gpt-5.6-terra implementer
    # változatlanul NEM ütközik. A közös Pro-ELŐFIZETÉS a 2026-08-20-i
    # user-döntés tudatos vállalása (a lejáró keret égetése), nem mérési rés.
    sol)
      row=$(engine_registry_row "$2") || return 1
      [ "$(printf '%s' "$row" | cut -f4)" = "$sol_model" ]
      ;;
    *) return 1 ;;
  esac
}

# A kör-ág prefixéből méri a MÁR COMMITOLT implementert, a
# docs/execution/engine-registry.tsv `name` oszlopával azonos kulcson
# (`sonnet-impl/e06-r23-…` → `sonnet-impl`). Üres kimenet, ha a körhöz még
# nincs távoli ág (friss dispatch — a D2 nem alkalmazható).
#
# A slug-illesztés szándékosan szűk (kötelező `-` a slug UTÁN): egy `ops/*`
# vagy elgépelt ág soha nem illeszkedhet egy kör-azonosítóra (ADR 0242 §9
# kockázat), és pl. `E06-R2` sosem illeszkedik `e06-r23-…`-ra.
resolve_branch_implementer() {   # $1=kör-azonosító → motor neve, vagy üres
  local round="${1:-}" slug branch
  [ -n "$round" ] || return 0
  slug=$(printf '%s' "$round" | tr '[:upper:]' '[:lower:]')
  branch=$(git ls-remote --heads "$round_remote" 2>/dev/null \
    | grep -oE "refs/heads/[^/[:space:]]+/${slug}-[^[:space:]]*" \
    | head -1) || true
  [ -n "$branch" ] || return 0
  branch=${branch#refs/heads/}
  printf '%s\n' "${branch%%/*}"
}

# Kiírja, hogy a megadott orchestrátor MOST elérhető-e (F2, review finding):
# a `claude` a kvóta-/session-zárlat alatt NEM elérhető, még akkor sem, ha az
# identitása független az implementertől; a `terra` a `fallback_engine=none`
# alatt nem elérhető. Az elérhetőség és a függetlenség két különböző kérdés —
# egyik sem helyettesítheti a másikat (ADR 0242 §5.2).
orchestrator_available() {   # $1=orchestrátor(claude|terra|sol)
  case "$1" in
    claude)
      claude_unavailable_until >/dev/null && return 1
      claude_usage_block_until >/dev/null && return 1
      return 0
      ;;
    # A Sol a Codex-oldalon fut (ugyanaz a CODEX_HOME, mint a Terráé), ezért
    # az elérhetősége is a Codex-oldali kapcsolóhoz kötött.
    terra | sol) [ "$fallback_engine" != "none" ] ;;
    *) return 1 ;;
  esac
}

# A dispatch ELŐTTI újravalidálás: adott kör + ágról mért implementer mellett
# melyik orchestrátor független ÉS elérhető. Feloldási sorrend (ADR 0242 §5.2,
# kötött):
#   1. a körhöz (D1 szerint) rögzített orchestrátor, ha független ÉS elérhető;
#   2. ha nem: a másik orchestrátor (claude|terra), ha független ÉS elérhető;
#   3. ha egyik sem: HALT_INDEP — fail-closed.
# Ismeretlen (registryből fel nem oldható) motor-prefix is HALT_INDEP: a
# függetlenség BIZONYÍTANDÓ, nem vélelmezendő (ADR 0242 §5.3). A rögzített
# orchestrátor függetlensége önmagában NEM elég ok a megtartására — ha
# elérhetetlen, a mozgatható szereplő (az orchestrátor) billen tovább, az
# implementer marad fix (ADR 0242 §5.2 "NEM elfogadható gyengítés").
resolve_resume_orchestrator() {   # $1=kör $2=ág-mért implementer → orchestrátor | HALT_INDEP
  local round="${1:-}" implementer="${2:-}" pinned candidate

  if [ -z "$round" ] || [ -z "$implementer" ]; then
    printf 'HALT_INDEP\n'
    return 0
  fi

  engine_registry_row "$implementer" >/dev/null 2>&1 || { printf 'HALT_INDEP\n'; return 0; }

  pinned=$(next_orchestrator "$round")
  if ! orchestrator_conflicts_with_implementer "$pinned" "$implementer" \
     && orchestrator_available "$pinned"; then
    printf '%s\n' "$pinned"
    return 0
  fi

  for candidate in claude terra; do
    [ "$candidate" != "$pinned" ] || continue
    if ! orchestrator_conflicts_with_implementer "$candidate" "$implementer" \
       && orchestrator_available "$candidate"; then
      mkdir -p "$orch_round_dir"
      printf '%s\n' "$candidate" > "$orch_round_dir/$round"
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  printf 'HALT_INDEP\n'
}

# --- Teszthorgok ----------------------------------------------------------
# A mérce futtatható artefaktum legyen, ne prompt-szöveg (docs/LESSONS.md):
# az önjavítás két gépi döntése kívülről is lekérdezhető, ezért tesztelhető.
case "${1:-}" in
  --status-file-for)   # $2=kör → a kör-kulcsolt állapotfájl útvonala (ADR 0272)
    round_status_file_for "${2:?}"
    exit 0
    ;;
  --heal-attempts)   # $2=kör $3=halt-kód → eddigi kísérletek száma
    heal_attempts "${2:-}" "${3:-}"
    exit 0
    ;;
  --gate-fingerprint)
    printf 'tests=%s %s\n' "$(gate_test_count)" "$(gate_artifact_hashes)"
    exit 0
    ;;
  --heal-pr-number)   # $2=heal branch → a hozzá tartozó merge-elt PR száma (üres, ha nincs)
    heal_pr_number "${2:-}"
    exit 0
    ;;
  --heal-pr-gate-violation)   # $2=PR szám → kiírja az okot, exit 0 ha a heal saját diffje gyengítette a mércét, exit 1 ha nem
    if heal_pr_gate_violation "${2:-}"; then
      exit 0
    else
      exit 1
    fi
    ;;
  --independent-engine)    # $2=queue-motor [$3=orchestrátor] → a FÜGGETLENSÉG által feloldott implementer motor, vagy HALT_INDEP (ADR 0138)
    resolve_independent_engine "${2:-}" "${3:-}"
    exit 0
    ;;
  --orchestrator-engine)   # melyik motor vinné MOST a review-t (ADR 0115 + 0222 rotáció + Sol-pin)
    case "$(next_orchestrator)" in
      terra) printf '%s\n' "$fallback_engine" ;;
      sol)   printf 'sol\n' ;;
      *)     printf 'claude\n' ;;
    esac
    exit 0
    ;;
  --next-orchestrator)     # [$2=kör] → a rotáció döntése: claude | terra (ADR 0222); kör-argumentummal körönként rögzített (ADR 0242 D1)
    next_orchestrator "${2:-}"
    exit 0
    ;;
  --branch-implementer)   # $2=kör → az ágról MÉRT implementer motor, vagy üres ha nincs kör-ág (ADR 0242 D2)
    resolve_branch_implementer "${2:-}"
    exit 0
    ;;
  --resume-orchestrator)   # $2=kör $3=ág-mért implementer → orchestrátor | HALT_INDEP (ADR 0242 D2)
    resolve_resume_orchestrator "${2:-}" "${3:-}"
    exit 0
    ;;
  --claude-session-pct)    # $2=session-napló → az utolsó mért keret-százalék
    claude_session_pct "${2:-/dev/null}"
    exit $?
    ;;
  --claude-session-reset-epoch)   # $2=session-napló → a banner reset-ideje epochban
    claude_session_reset_epoch "${2:-/dev/null}"
    exit $?
    ;;
  --claude-limit-check)    # $2=session-napló → 0, ha kvótakimerülés nyoma van
    grep -qEi "$CLAUDE_LIMIT_PATTERN" "${2:-/dev/null}" 2>/dev/null
    exit $?
    ;;
  --claude-process-comm-check)    # $2=`ps -o comm=` név → 0, ha ez ÉLŐ Claude process
    printf '%s\n' "${2:-}" | grep -qE "$CLAUDE_PROCESS_COMM_PATTERN"
    exit $?
    ;;
  --session-config)    # $2=round|heal → a feloldott modell + effort (teszthorog, user-döntés 2026-08-04)
    case "${2:-}" in
      # $3 = implementer motor (opcionális): a KÖRRE feloldott pár. Enélkül a
      # globális default — a régi hívási alak bitre változatlan.
      round) printf 'model=%s effort=%s\n' "$(orch_pair_model "${3:-}")" "$(orch_pair_effort "${3:-}")" ;;
      heal)  printf 'model=%s effort=%s\n' "$heal_model" "$claude_effort" ;;
      *) echo "használat: --session-config round|heal" >&2; exit 2 ;;
    esac
    exit 0
    ;;
  --working-tree-dirt)    # a szűrt munkafa-szennyeződés (teszthorog, 2026-08-23)
    working_tree_dirt
    printf '\n'
    exit 0
    ;;
  --engine-runnable)    # $2=motor → exit 0, ha futtatható (teszthorog, 2026-08-23)
    engine_is_runnable "${2:-}"
    exit $?
    ;;
  --resume-implementer)    # $2=kör → a folytatás implementere a runnability-őr UTÁN
    resume_implementer_for "${2:-}"
    printf '\n'
    exit 0
    ;;
  --terra-hold-active)    # $2=kör → exit 0 ha AKTÍV Terra napi-budget hold van rá, 1 egyébként
    if terra_hold_active_for "${2:-}"; then
      exit 0
    else
      exit 1
    fi
    ;;
  --terra-hold-if-exhausted)    # $2=kör → teszthorog: meghívja terra_hold_if_exhausted-et (E03-R08 H6 2. javítás)
    terra_hold_if_exhausted "${2:-}"
    exit 0
    ;;
  --codex-usage-limit-hold-active)    # $2=kör → exit 0 ha AKTÍV Codex CLI usage-limit hold van rá, 1 egyébként
    if codex_usage_limit_hold_active_for "${2:-}"; then
      exit 0
    else
      exit 1
    fi
    ;;
  --claude-quota-hold-if-detected)    # $2=kör $3=session-napló → teszthorog (E13-R16 mérés)
    claude_quota_hold_if_detected "${2:-}" "${3:-}"
    exit $?
    ;;
  --claude-quota-hold-active)    # $2=kör → teszthorog: aktív-e a Claude-kvóta hold
    claude_quota_hold_active_for "${2:-}"
    exit $?
    ;;
  --codex-usage-limit-hold-if-detected)    # $2=kör $3=szöveg → teszthorog: meghívja codex_usage_limit_hold_if_detected-et (E05-R15 H6 önjavítás)
    codex_usage_limit_hold_if_detected "${2:-}" "${3:-}"
    exit 0
    ;;
  --codex-usage-limit-reset-epoch)    # $2=szöveg → teszthorog: a kinyert epoch stdoutra, kilépés 1 illeszkedés nélkül
    codex_usage_limit_reset_epoch_from_text "${2:-}"
    exit $?
    ;;
  --handle-round-halt)    # $2=kör $3=status-fájl $4=session-napló → teszthorog: a HALT ELSŐ észlelésének útvonala (E03-R08 H6 5. javítás)
    handle_round_halt "${2:-}" "${3:-}" "${4:-}"
    exit 0
    ;;
  --terra-clear-stale-halt)    # $2=kör → teszthorog: meghívja terra_clear_stale_halt_for-ot (E03-R08 H6 7. javítás)
    terra_clear_stale_halt_for "${2:-}"
    exit 0
    ;;
  --main-sync-strategy)    # $2=munkafa-útvonal (cwd a teszt-repo) → D1 teszthorog: kiírja, hogy a driver ezen a fán melyik ágat venné (noop | ff-merge | halt:<oka>), exit 0/1/2
    (
      cd "${2:-$repo_root}" || exit 50
      local_head_sha=$(git rev-parse HEAD 2>/dev/null) || { echo "halt:nincs-repo"; exit 1; }
      remote_main_sha=$(git rev-parse origin/main 2>/dev/null) || { echo "halt:nincs-origin"; exit 1; }
      if [ "$local_head_sha" = "$remote_main_sha" ]; then
        echo "noop:${local_head_sha:0:7}"
        exit 0
      fi
      if git merge-base --is-ancestor "$local_head_sha" "$remote_main_sha" 2>/dev/null; then
        echo "ff-merge:${local_head_sha:0:7}->${remote_main_sha:0:7}"
        exit 0
      fi
      echo "halt:divergencia:${local_head_sha:0:7}↛${remote_main_sha:0:7}"
      exit 1
    )
    rc=$?; exit "$rc"
    ;;
  --main-sync-ff-merge)    # $2=munkafa-útvonal → D1 teszthorog: valóban végrehajtja a ff-merge-et (a fenti stratégia csak kiírja), exit 0 siker / 1 már azonos / 2 divergencia / 3 piszkos fa (előfeltétel)
    (
      cd "${2:-$repo_root}" || exit 50
      # D1 piszkos-fa előfeltétel-őr (ADR 0175 §2, E99-R19 brief §4 4. cella):
      # a `main_sync_strategy` a driver 3. Előfeltételek szakaszában a `die`
      # miatt sosem fut piszkos fán, de a teszthorog itt is tükrözi ezt a
      # viselkedést — különben a "main lemaradt + piszkos fa" mérőcella a
      # "noop" / "divergencia" szerencsés egybeeséssel lenne piros, és a
      # piszkos-fa őr kikerülése észrevétlen maradna (F1 review).
      if [ -n "$(git status --porcelain)" ]; then
        echo "halt:dirty-tree"
        exit 3
      fi
      local_head_sha=$(git rev-parse HEAD 2>/dev/null) || exit 50
      remote_main_sha=$(git rev-parse origin/main 2>/dev/null) || exit 50
      if [ "$local_head_sha" = "$remote_main_sha" ]; then
        echo "noop"
        exit 1
      fi
      if git merge-base --is-ancestor "$local_head_sha" "$remote_main_sha" 2>/dev/null; then
        git merge --ff-only "$remote_main_sha" 2>&1
        exit 0
      fi
      echo "divergencia"
      exit 2
    )
    rc=$?; exit "$rc"
    ;;
  --pending-done-failsafe-required)    # $2=sor-fájl-útvonal $3=kör → D2 teszthorog: a `sed` parancs hatására a sor piszkos lesz-e (a fail-safe `chore(pipeline)` commit szükséges), exit 0 ha kell / 1 ha nem
    queue="${2:-}"
    round="${3:-}"
    [ -n "$queue" ] && [ -n "$round" ] || exit 3
    tmp=$(mktemp)
    sed -e "s|^\($round\t.*\t\)pending$|\1done|" "$queue" > "$tmp"
    if ! diff -q "$queue" "$tmp" >/dev/null 2>&1; then
      rm -f "$tmp"
      exit 0
    fi
    rm -f "$tmp"
    exit 1
    ;;
  --requested-slots)    # a feloldott KÉRT slotszám a RAM-őr ELŐTT (file > env > default)
    printf '%s\n' "$slots"
    exit 0
    ;;
  --effective-slots)    # $2=kért slotszám → a RAM-fedezet szerinti tényleges (ADR 0171 §1)
    effective_slots "${2:-$slots}"
    exit 0
    ;;
  --slot-lock-path)    # $2=slot sorszám → a slot zárfájlja (a slot 1 a régi `lock`)
    slot_lock_path "${2:-1}"
    exit 0
    ;;
  --spawn-next-firing)    # teszthorog: a merge utáni azonnali lánc-folytatás ága
    # NINCS `wait`: a gyerek SZÁNDÉKOSAN a szülő halálára vár (a slot-zár
    # elengedésére), tehát a szülő megvárása holtpont lenne.
    spawn_next_firing
    exit 0
    ;;
  --brief-lint)    # $2=kör $3=brief → a pre-flight lint-jelentés útvonala (ADR 0171 §4)
    write_brief_lint "${2:-}" "${3:-}"
    exit 0
    ;;
esac

# --- 1. Zár (slot-alapú, ADR 0171) ---------------------------------------
# A `flock -n` NEM blokkol: ha minden slot foglalt, ez a firing egyszerűen
# kihagyja magát. Cron-nál pontosan ez a kívánt viselkedés.
#
# PIPELINE_SLOTS=1 (alapértelmezés) mellett a slot 1 zára ugyanaz a `lock`
# fájl, ami eddig is volt — a viselkedés és az üzenet változatlan.
slots=$(effective_slots "$slots")
slot_acquired=0
slot_candidate=1
while [ "$slot_candidate" -le "$slots" ]; do
  exec 9>"$(slot_lock_path "$slot_candidate")"
  if flock -n 9; then
    slot_index=$slot_candidate
    slot_acquired=1
    break
  fi
  slot_candidate=$(( slot_candidate + 1 ))
done
if [ "$slot_acquired" != "1" ]; then
  if [ "$slots" -eq 1 ]; then
    log "zár foglalt — már fut egy kör, ez a firing kimarad"
  else
    log "minden slot foglalt ($slots) — ez a firing kimarad"
  fi
  exit 0
fi
[ "$slots" -gt 1 ] && log "slot $slot_index/$slots megszerezve (futó körök: $(inflight_rounds | tr '\n' ' '))"

# --- 1.5 Terra napi-budget felfüggesztés (E03-R08 H6 önjavítás) -----------
# Ha egy pozitív vészlimit mellett egy korábbi retry MÉRVE találta a napi
# Terra-budgetet kimerültnek, a hold-fájl UTC éjfélig felfüggeszti a rá
# vonatkozó firing-okat. Korlátlan policyre váltáskor az elavult hold törlődik.
# A hold
# a HALTOLT kör sorára, vagy — ha épp nincs halt — a sorban következő
# 'pending' körre vonatkozik (ugyanaz a kör, ha a lánc még nem jutott tovább).
active_round=""
if [ -f "$halt_file" ]; then
  active_round=$(grep -m1 '^round=' "$halt_file" | cut -d= -f2-)
elif [ -f "$queue_file" ]; then
  active_round=$(grep -v '^[[:space:]]*#' "$queue_file" | grep -P '\tpending$' | head -1 | cut -f1)
fi
if [ -n "$active_round" ] && terra_hold_active_for "$active_round"; then
  exit 0
fi
# Codex CLI usage-limit hold (E05-R15 H6 önjavítás) — ugyanaz a "csendes
# kihagyás" elv, más réteg: a Codex CLI ALATT futó fiók (bármelyik
# motor-profil) tényleges upstream kvótája, nem a router belső számlálója.
if [ -n "$active_round" ] && codex_usage_limit_hold_active_for "$active_round"; then
  exit 0
fi
# Claude-előfizetés kvóta-hold (E13-R16 mérés) — a harmadik motor-réteg,
# ugyanazzal a szerződéssel: se session, se önjavítási kísérlet a reset előtt.
if [ -n "$active_round" ] && claude_quota_hold_active_for "$active_round"; then
  exit 0
fi
[ -n "$active_round" ] && terra_clear_stale_halt_for "$active_round"

# --- 1c. A GitHub-PAT lejárata (ADR 0495 D4) ------------------------------
# MÉRVE 2026-08-28: a lejárt token `H-AUTH`-tal állította meg a láncot, 57
# firingen (~4,75 óra) át, és a hibaosztály DÁTUMOZOTT — tehát előre látható.
# A `gh` a saját válaszfejlécében megmondja a lejáratot; ezt naponta párszor
# megkérdezzük, és a küszöb alatt szólunk, MIELŐTT a lánc megáll.
gh_token_expiry_probe() {   # → a lejárat ISO-alakja a stdouton, vagy 1
  if [ -n "${PIPELINE_GH_EXPIRY_CMD:-}" ]; then
    eval "$PIPELINE_GH_EXPIRY_CMD"
    return $?
  fi
  timeout 20 gh api -i user 2>/dev/null \
    | grep -im1 '^Github-Authentication-Token-Expiration:' \
    | cut -d: -f2- \
    | sed 's/^ *//; s/ *$//'
}

gh_token_expiry_days() {   # → hány NAP múlva jár le a PAT, vagy 1
  local now cached cached_epoch expiry expiry_epoch probe_seconds
  now=$(pipeline_now_epoch)
  case "$gh_token_probe_h" in ''|*[!0-9]*) return 1 ;; esac
  probe_seconds=$(( gh_token_probe_h * 60 * 60 ))
  if [ -f "$gh_token_expiry_file" ]; then
    cached=$(head -1 "$gh_token_expiry_file")
    cached_epoch=${cached%%|*}
    expiry=${cached#*|}
    case "$cached_epoch" in
      ''|*[!0-9]*) ;;
      *) [ "$now" -lt "$(( cached_epoch + probe_seconds ))" ] || expiry="" ;;
    esac
  fi
  if [ -z "${expiry:-}" ]; then
    expiry=$(gh_token_expiry_probe) || return 1
    [ -n "$expiry" ] || return 1
    printf '%s|%s\n' "$now" "$expiry" > "$gh_token_expiry_file"
  fi
  expiry_epoch=$(date -d "$expiry" +%s 2>/dev/null) || return 1
  printf '%s\n' "$(( (expiry_epoch - now) / 86400 ))"
}

check_gh_token_expiry() {
  local days
  case "$gh_token_warn_days" in ''|*[!0-9]*) return 0 ;; esac
  days=$(gh_token_expiry_days) || return 0
  [ "$days" -le "$gh_token_warn_days" ] || return 0
  if [ "$days" -le 2 ]; then
    log "GITHUB-TOKEN: $days nap múlva lejár — cseréld ki, különben a lánc H-AUTH-tal áll meg"
    notify "🔑 a GitHub-token $days nap múlva lejár" \
      "cseréld ki a ~/.git-credentials + gh auth párost, különben a lánc H-AUTH-tal áll meg" urgent
  else
    log "GITHUB-TOKEN: $days nap múlva lejár (küszöb: $gh_token_warn_days nap)"
    notify "🔑 a GitHub-token $days nap múlva lejár" \
      "küszöb: $gh_token_warn_days nap — tervezd be a cserét" high
  fi
}

check_gh_token_expiry

# --- 2. Halt-állapot → önjavítás (ADR 0112) -------------------------------
# A halt nem a lánc vége, hanem az önjavító kör bemenete. A driver ugyanezen a
# záron belül indítja: egyszerre továbbra is EGY session dolgozik.
if [ -f "$halt_file" ] && gateguard_hold_halted_round; then
  log "a gate-érintő kör hold-ra került — ez a firing a soron következő pending körrel folytatja"
fi
if [ -f "$halt_file" ]; then
  log "a lánc MEGÁLLT — $halt_file:"
  cat "$halt_file" >&2
  # Külső kimaradás alatt a javító kör nem tud mit javítani a repóban — a
  # keretet égetné el egy GitHub-oldali hibára (mérve 2026-08-06).
  if github_actions_degraded; then
    log "az önjavítás KIMARAD: GitHub Actions incidens alatt a halt oka külső — a lánc a helyreállás után próbálja újra"
    exit 3
  fi
  if attempt_selfheal; then
    log "az önjavítás feloldotta a láncot; a következő firing viszi a kört"
    exit 0
  fi
  log "a lánc továbbra is áll — feloldás: tools/pipeline-status.sh --resume"
  exit 3
fi

# --- 3. Előfeltételek -----------------------------------------------------
[ -f "$queue_file" ]      || die "hiányzik a sor-fájl: $queue_file"
[ -f "$prompt_template" ] || die "hiányzik a prompt-sablon: $prompt_template"
command -v "$claude_bin" >/dev/null || die "nincs claude CLI: $claude_bin"
command -v gh >/dev/null            || die "nincs gh CLI"

git fetch -q origin main || die "git fetch origin main sikertelen"

current_branch=$(git rev-parse --abbrev-ref HEAD)
if [ "$current_branch" != "main" ]; then
  # MÉRVE 2026-08-05: egy másik session a KÖZÖS munkafát a `gov/03-...` ágon
  # hagyta, és a lánc emiatt esett ki egy firingre. Tiszta fánál ez maradék,
  # nem folyamatban lévő munka: a körök külön munkapéldányban dolgoznak.
  #
  # MÉRVE 2026-08-13 (E99-R08 review F1, portolva E99-R08/H3 self-heal alatt):
  # ez a VALÓDI `git checkout` a `PIPELINE_STATE_DIR`-t injektáló
  # tesztfutásokban a MEGOSZTOTT munkafa ágát mozgatja el a vizsgált
  # kör-ágról — a `tools/tests` legtöbb esete izolált állapotot kap, de a
  # jelen munkafa VALÓDI git ága nem izolált. Teszt-módban (PIPELINE_STATE_DIR
  # beállítva; a production cron soha nem állítja, l. a fenti alapértelmezést)
  # fail-closed: nem nyúl a munkafa ágához.
  if [ -n "${PIPELINE_STATE_DIR:-}" ]; then
    die "a munkafa nem a main-en van ($current_branch) — teszt-módban (PIPELINE_STATE_DIR) a driver nem mozdítja a megosztott munkafa ágát"
  fi
  if [ -z "$(git status --porcelain)" ] && git checkout -q main 2>/dev/null; then
    log "munkafa-helyreállítás: $current_branch → main (tiszta fa, maradék ág)"
    current_branch=main
  else
    die "a munkafa nem a main-en van ($current_branch) és nem tiszta — a lánc csak tiszta main-ről indul"
  fi
fi
tree_dirt=$(working_tree_dirt)
if [ -n "$tree_dirt" ]; then
  die "piszkos munkafa — a lánc nem indul ismeretlen lokális változás fölé: $(printf '%s' "$tree_dirt" | tr '\n' ' ')"
fi
# D1 (E99-R19): a main-szinkron három, ma még összemosott esetre bontása —
# (a) azonos, (b) kizárólag LEMARADÁS (origin/main szigorúan előre van, a
# lokális HEAD az őse), (c) VALÓDI DIVERGENCIA (lokális commit, ami nincs
# az originen). A (b) a mért többség (2026-08-11..08-18 között 9 firing, egy
# 18 perces epizódban 4 egymás után) — a lánc olyasmire várt, amit maga is
# el tud végezni `git merge --ff-only`-val. A fa fenti piszkos-ellenőrzése
# (`git status --porcelain` üres) garantálja, hogy az ff-merge nem hoz
# konfliktust; a main-ágon való állás a fenti `current_branch=main` feltétel
# alatt biztosított. A piszkos fa és a nem-main ág esete a fenti `die`
# hívásokkal változatlanul megáll — az „előbb rendezd" üzenet csak akkor
# jelenik meg, ha VALÓDI divergencia van.
main_sync_strategy   # a `$local_head_sha` / `$remote_main_sha` változókat a
                    # függvény tölti ki, és `git merge --ff-only`-t is az
                    # indít (a chain.log-ba log-ozza a régi→új HEAD-et)
                    # vagy `die`-val megáll divergencia esetén. Külön
                    # függvény, hogy a tesztelhetőség ne függjön a driver
                    # teljes, külső függőségekkel terhelt főágától —
                    # l. tools/tests/test_chain_hygiene.py.

# Párhuzamos autonóm driver ezen a boxon MÉRT jelenség (memória, E02-R01):
# nyitott PR vagy futó workflow = valaki más visz egy kört. A SAJÁT, futó
# köreink branch-ei viszont nem „valaki más" — slot-módban ezeket kiszűrjük.
inflight_branch_pattern() {   # regex a futó körök kisbetűs azonosítóiból (üres, ha nincs)
  local pattern="" round lower
  for round in $(inflight_rounds); do
    lower=$(printf '%s' "$round" | tr 'A-Z' 'a-z')
    pattern="${pattern:+$pattern|}$lower"
  done
  printf '%s\n' "$pattern"
}

# MÉRVE 2026-08-15 (E99-R13 H3 2. önjavítás): egy megállt kör NYITOTT PR-t
# hagyhat maga után — push + PR + review UTÁN, de merge ELŐTT halt (pontosan
# ez történt: PR #266). Az `inflight_rounds()` viszont csak AMÍG egy session
# fut van kitöltve; minden script-kilépéskor törlődik (trap, lásd lentebb).
# A KÖVETKEZŐ firing tehát üres `own_branches`-szel indul, és a SAJÁT, még
# nyitott kör-PR-jét idegennek látja: `die "nyitott PR van"` minden firingen,
# örökre — az önjavítás UTÁN sem halad a lánc, jelzés és értesítés nélkül
# (exit 4, nem HALT). A sor-fájl NEM 'done' sora perzisztens „ez a miénk" jel,
# túlél egy session-határt — ellentétben az `inflight_dir`-rel.
queue_active_branch_pattern() {   # regex a sor-fájl NEM 'done' körazonosítóiból (üres, ha nincs)
  local pattern="" round _brief _engine _adr status lower
  [ -f "$queue_file" ] || { printf '%s\n' ""; return; }
  while IFS=$'\t' read -r round _brief _engine _adr status; do
    case "$round" in ''|'#'*) continue ;; esac
    [ "$status" = "done" ] && continue
    lower=$(printf '%s' "$round" | tr 'A-Z' 'a-z')
    pattern="${pattern:+$pattern|}$lower"
  done < <(grep -v '^[[:space:]]*#' "$queue_file")
  printf '%s\n' "$pattern"
}
own_branches=$(inflight_branch_pattern)
queue_branches=$(queue_active_branch_pattern)
[ -n "$queue_branches" ] && own_branches="${own_branches:+$own_branches|}$queue_branches"

# Egy branch akkor tartozik KÖRHÖZ, ha a nevében ott a kör-azonosító
# (`codex/e04-r15-…`, `heal/E04-R15-H3-1`, `minimax/e02-r18-…`). MÉRVE: minden
# eddigi kör-branch ilyen; a `ops/`, `gov/`, `chore/` ágak governance-munkák.
#
# MIÉRT KELL (mérve 2026-08-05): két saját infra-PR miatt a lánc KILENC
# firinget hagyott ki (~45 perc), pedig azok a PR-ek egyetlen körrel sem
# versenyeztek. Az őr eredeti célja a párhuzamos KÖR-driver kiszűrése volt.
ROUND_BRANCH_PATTERN='[eE][0-9]{2}-[rR][0-9]{2}'

count_foreign() {   # stdin: branch-nevek → a NEM sajátok száma (csak kör-branchek)
  local rounds_only
  rounds_only=$(grep -E "$ROUND_BRANCH_PATTERN" || true)
  [ -n "$rounds_only" ] || { echo 0; return; }
  # Kis-nagybetű-független: a kör-branch `codex/e04-r15-…`, az önjavító ág
  # viszont `heal/E04-R15-H3-1` alakú (mérve 2026-08-05) — ugyanaz a kör.
  if [ -n "$own_branches" ]; then
    printf '%s\n' "$rounds_only" | grep -Evi "$own_branches" | grep -c '[^[:space:]]' || true
  else
    printf '%s\n' "$rounds_only" | grep -c '[^[:space:]]' || true
  fi
}

open_pr_branches=$(gh pr list --state open --json headRefName --jq '.[].headRefName' 2>/dev/null) \
  || open_pr_branches="?"
[ "$open_pr_branches" = "?" ] && die "a nyitott PR-ek nem kérdezhetők le (gh) — a lánc nem indul vakon"
open_prs=$(printf '%s\n' "$open_pr_branches" | count_foreign)
[ "$open_prs" = "0" ] || die "nyitott PR van ($open_prs) — másik kör lehet folyamatban"

# A `main`-en FUTÓ workflow a saját merge utáni docs/sor-pushunk CI-ja: az
# ADR 0086 óta a build-apk nem is indul main-push-ra, a Router CI pedig a
# dokumentum-diffet méri. Ezt megvárni MÉRT holtidő volt (2026-08-05: a merge
# és a következő kör indulása között ez adott egy teljes firing-kihagyást),
# miközben nem védett semmit. Cserébe KEMÉNYEBB kaput kap a lánc: piros main
# fölé nem indulunk (ezt korábban SEMMI nem ellenőrizte).
# A 60 percnél régebben `queued` futás NEM másik kör: a GitHub sosem ütemezte
# be. MÉRT eset (2026-08-06, Actions major outage): egy 17:32-kor sorba állt
# `Full Gate` futás 3,5 órán át `queued` maradt, a GitHub sem kilőni
# („Cannot cancel a workflow run that is completed"), sem törölni (403) nem
# engedte — és közben MINDEN firinget kiejtett a „fut egy workflow" előfeltétel.
stale_queued_minutes=${PIPELINE_STALE_QUEUED_MINUTES:-60}
running_branches=$(gh run list --limit 20 --json status,headBranch,createdAt,databaseId \
  --jq '.[] | select(.status != "completed") | [.headBranch, .createdAt, (.databaseId|tostring), .status] | @tsv' \
  2>/dev/null) || running_branches="?"
if [ "$running_branches" != "?" ] && [ -n "$running_branches" ]; then
  running_branches=$(
    printf '%s\n' "$running_branches" | while IFS=$'\t' read -r branch created run_id state; do
      [ -n "$branch" ] || continue
      age_minutes=$(( ( $(date +%s) - $(date -d "$created" +%s 2>/dev/null || echo 0) ) / 60 ))
      if [ "$state" = "queued" ] && [ "$age_minutes" -ge "$stale_queued_minutes" ]; then
        log "BERAGADT FUTÁS: #$run_id ($branch) ${age_minutes} perce 'queued' — nem számít futó körnek"
        continue
      fi
      printf '%s\n' "$branch"
    done
  )
fi
[ "$running_branches" = "?" ] && die "a futó workflow-k nem kérdezhetők le (gh) — a lánc nem indul vakon"
running_runs=$(printf '%s\n' "$running_branches" | grep -v '^main$' | count_foreign)
[ "$running_runs" = "0" ] || die "fut egy workflow ($running_runs) — megvárjuk"

# A main egészsége MINDKÉT sávon (ADR 0174). MÉRVE: a 2026-08-05-i három
# önjavító körből egy (E04-R15/H3) pontosan azért kellett, mert a main
# ÖRÖKÖLT piros gate-tel élt, és ez a KÖVETKEZŐ kör merge-kapuját fogta meg.
# A Router CI a dokumentum/tooling sávot méri, a full-gate a Flutter-mércét —
# egyik sem helyettesíti a másikat.
main_head=$(git rev-parse origin/main)
for main_workflow in router-ci.yml full-gate.yml; do
  # A SHA ÖSSZES futását nézzük, nem csak a legutolsót (user-szabály 2026-08-06:
  # „figyeld a GitHub-értesítéseket is"). MÉRT okok, amiért a legutolsó futás
  # önmagában félrevezet:
  #   * duplikált dispatch → az egyik futás `cancelled`, pedig a fa zöld;
  #   * GitHub-infra hiba → `Set up job` bukik („Failed to resolve action
  #     download info: Service Unavailable"), miközben ugyanazon a SHA-n van
  #     sikeres futás. Ilyenkor a lánc FELESLEGESEN állna.
  main_runs=$(gh run list --workflow "$main_workflow" --branch main --limit 10 \
    --json headSha,conclusion,status \
    --jq "[.[] | select(.headSha == \"$main_head\") | select(.status == \"completed\")] | map(.conclusion) | join(\",\")" \
    2>/dev/null) || main_runs="?"
  case "$main_runs" in
    "?")
      log "figyelem: a main $main_workflow állapota nem kérdezhető le — a lánc a többi kapu alapján indul"
      ;;
    "")
      : ;;   # ezen a SHA-n még nem futott le — nincs mit mérni
    *success*)
      : ;;   # van sikeres futás a jelenlegi main-en: a fa zöld
    *failure* | *timed_out* | *startup_failure* | *action_required*)
      if github_actions_degraded; then
        log "a main $main_workflow [$main_runs] pirosa GITHUB-INCIDENS alatt keletkezett — nem a fa hibája, a lánc vár a helyreállásra"
        exit 0
      fi
      notify "⛔ piros main" "$main_workflow a main ($(git rev-parse --short origin/main)) tetején: $main_runs" high
      die "a main $main_workflow futása(i) [$main_runs] pirosak a jelenlegi SHA-n — a lánc nem indul piros main fölé"
      ;;
    *) : ;;
  esac
done

# --- 4. A következő kör kiválasztása --------------------------------------
# Egy slot mellett a sor ELEJE következik, változatlanul. Több slot mellett a
# választás gépi: `tools/round-slots.py` csak olyan kört enged, amely (a) a
# futókkal fájl-diszjunkt és (b) minden előfeltétele `done`. Az „előfeltétel"
# forrása ADR 0495 D1 óta a brief KIMONDOTT `Előfeltétel` sora — a futó kör NEM
# számít teljesítettnek, mert a benne születő API még nem létezik. Amelyik brief
# nem mondja ki, arra a régi, epicen belüli sorosítás él (fail-closed).
if [ "$slots" -gt 1 ] && [ -f "$repo_root/tools/round-slots.py" ]; then
  selected_round=$(python3 "$repo_root/tools/round-slots.py" --repo "$repo_root" \
    --inflight "$inflight_dir" plan --slots "$slots" --limit 1 --format round 2>/dev/null | head -1)
  if [ -z "$selected_round" ]; then
    log "nincs a futókkal diszjunkt, előfeltétel-kész kör — ez a firing kimarad"
    exit 0
  fi
  next_line=$(grep -v '^[[:space:]]*#' "$queue_file" | grep -P "^$selected_round\t" | grep -P '\tpending$' | head -1)
else
  next_line=$(grep -v '^[[:space:]]*#' "$queue_file" | grep -P '\tpending$' | head -1)
fi
if [ -z "$next_line" ]; then
  log "a sorban nincs több 'pending' kör — a lánc végigért"
  exit 0
fi

round=$(printf '%s' "$next_line" | cut -f1)

# MÉRT hiba (2026-08-15, az ELSŐ PIPELINE_SLOTS=2 firing): a kör-állapotfájl
# GLOBÁLIS volt (`$state_dir/round-status`), ezért két párhuzamos driver
# ugyanazt a fájlt törölte, írta és olvasta. Az E14-R01 így az E07-R04
# `outcome=merged` sorát olvasta ki, és MUNKA NÉLKÜL lett `done` — az
# értesítése szó szerint a másik kör összefoglalója volt (0 recognition flag,
# nincs release-guard doksi, nincs PR). A slot-VÁLASZTÁS helyes volt
# (`tools/round-slots.py` mérve diszjunktot adott); a hiba a kör-ÁLLAPOT
# megosztásában. Kör-kulcsolt fájl, hogy két slot ne lássa egymás eredményét.
status_file=$(round_status_file_for "$round")
brief=$(printf '%s' "$next_line" | cut -f2)
engine=$(printf '%s' "$next_line" | cut -f3)
adr=$(printf '%s' "$next_line" | cut -f4)

[ -f "$brief" ] || die "a kör briefje nem létezik: $brief"

# --- 4.1 MÉRCE-őr pre-flight (ADR 0321) -----------------------------------
# A `H-GATEGUARD` halt gyökéroka MÉRVE (E99-R17, 2026-08-19) TERVEZÉSI hiba:
# a brief `allowed_paths` listáján olyan fájl szerepel, amit a
# `.claude/hooks/protect_factory_files.py` véd. Ezt a kör NEM tudja megoldani —
# sem markerrel, sem újrapróbálással (docs/LESSONS.md L322–L323) —, tehát a
# session elindítása garantáltan elpazarolt implementer-futás és egy halt.
# Az ütközést a dispatch ELŐTT mérjük, a védett listát magából az őrből
# importálva (tools/gateguard-scan.py), és a kört a sorban hold-ra tesszük:
# az emberi döntés megmarad, a lánc viszont megy tovább a következő körrel.
if [ "${PIPELINE_GATEGUARD_PREFLIGHT:-1}" = "1" ] && [ -f "$repo_root/tools/gateguard-scan.py" ]; then
  gateguard_conflicts=$(python3 "$repo_root/tools/gateguard-scan.py" --repo "$repo_root" --brief "$brief" 2>/dev/null) || gateguard_status=$?
  gateguard_status=${gateguard_status:-0}
  if [ "$gateguard_status" = "1" ]; then
    log "MÉRCE-ŐR PRE-FLIGHT: a(z) $round briefje védett fájlt kérne — $(printf '%s' "$gateguard_conflicts" | tr '\n' ' ')"
    if queue_hold_round "$round" "H-GATEGUARD pre-flight"; then
      gateguard_ledger_append "$round" "H-GATEGUARD-PREFLIGHT" "$(printf '%s' "$gateguard_conflicts" | tr '\n' ' ')"
      log "a(z) $round sora HOLD — emberi gate-döntés kell hozzá; a lánc a következő firingen a soron következő kört viszi"
      notify "⏸️ gate-érintő kör hold-on: $round" "a brief védett fájlt kérne — emberi döntés kell, a lánc megy tovább" high
      exit 0
    fi
    die "a(z) $round briefje védett fájlt kérne, és a sor hold-ra állítása nem sikerült — emberi döntés kell"
  fi
fi

# --- Motor-override (ADR 0140 + E99-R14 / ADR 0307 §1 D2) -----------------
# A motorok kvótája külön merül ki (a Terra 9%-on, 2026-08-05). Az override
# egyetlen gitignore-olt fájl, ezért a váltás visszavonható: törlésével a
# queue soronkénti `engine` értéke lép vissza életbe, konfiguráció-átírás
# nélkül. `tools/engine-profile.sh use|clear`.
#
# E99-R14 D2: az override-fájl a TTL-t és az indoklást is hordozza
# (3 soros alak, lásd `tools/engine-profile.sh`: `engine=`, `expires_at=`,
# `reason=`). A driver KÖR-KIVÁLASZTÁSKOR ellenőrzi a lejáratot:
#   - ha `expires_at` a múltban van, a fájl TÖRLŐDIK, a queue `engine`
#     értéke lép életbe (napló + ntfy);
#   - ha nincs `expires_at` (régi egysoros alak) ÉS a fájl mtime-ja
#     régebbi, mint `PIPELINE_OVERRIDE_WARN_HOURS` (alap 72), a driver
#     FIGYELMEZTET, de ÉL — a figyelem passzív, nem dönt helyette;
#   - a ntfy NAPONTA LEGFELJEBB EGYSZER megy ki (állapot-bélyeg a
#     `$state_dir`-ben), hogy ne zajosodjon a telefon;
#   - a futó kört a lejárat NEM érinti — a kör a saját motorjával fejezi be.
#
# M3 javítás: a kiértékelést a `tools/engine-profile.sh evaluate` CLI végzi
# (ugyanaz a függvény, amit a tesztek is hívnak — nincs duplikált logika).
# A driver itt CSAK a log/ntfy hívásokat és a motorváltozó frissítését
# végzi, a mérce-mátrix és a falszifikációs cellák a megosztott függvényt
# mérik.
override_file_mtime() { stat -c %Y "$engine_override_file" 2>/dev/null || echo 0; }
override_file_age_hours() {
  local mtime
  mtime=$(override_file_mtime)
  awk -v now="$(date +%s)" -v mt="$mtime" 'BEGIN { if (mt > 0) printf "%.2f", (now - mt) / 3600.0; else print "0" }'
}

engine_override_file="$state_dir/engine-override"
override_warn_threshold=${PIPELINE_OVERRIDE_WARN_HOURS:-72}
override_warn_state_file="$state_dir/override-warn-${override_warn_threshold}h.stamp"
if [ -f "$engine_override_file" ]; then
  # A kiértékelés a `engine-profile.sh evaluate` parancsra van bízva — így
  # a driver motor-override blokkja és a tesztek UGYANAZT a függvényt hívják
  # (M3: nincs duplikált logika, a korábbi `--engine-override-evaluate`
  # top-level hook törölve). A kimenet: stdout = <motor> | EXPIRED:<motor> | <empty>;
  # exit 0/1/2/3/4. A státuszt KÖZVETLENÜL a parancs után capture-öljük,
  # mert a `set -uo pipefail` nem állítja vissza a $?-t, de bármilyen
  # következő parancs felülírná.
  evaluate_output=$(bash "$repo_root/tools/engine-profile.sh" evaluate "$override_warn_threshold" 2>/dev/null)
  evaluate_status=$?
  engine_override=""
  case "$evaluate_status" in
    0)
      engine_override="$evaluate_output"
      [ "$engine_override" != "$engine" ] && \
        log "MOTOR-OVERRIDE: $engine → $engine_override (tools/engine-profile.sh clear old fel)"
      engine=$engine_override
      ;;
    1)
      # EXPIRED — a függvény már törölte a fájlt, ezért a motornevet a
      # strukturált kimenetből kell megőrizni az audit- és ntfy-eseményhez.
      expired_engine=${evaluate_output#EXPIRED:}
      if [ "$expired_engine" = "$evaluate_output" ] || [ -z "$expired_engine" ]; then
        die "a lejárt motor-override kiértékelése nem tartalmaz motornevet: $evaluate_output"
      fi
      log "MOTOR-OVERRIDE LEJÁRT: $expired_engine — a queue engine oszlopa lép vissza"
      notify "⏰ motor-override lejárt" "$expired_engine — a queue soronkénti engine értéke lép életbe" high
      ;;
    2)
      # STALE — a függvény a motornevet írta a stdout-ba, de a kor-
      # figyelmeztetés lép. A napló + a napi-egyszer ntfy a HÍVÓ dolga,
      # mert ezek a lánc-naplóhoz / ntfy-topic-hoz kötöttek.
      engine_override="$evaluate_output"
      age_hours=$(override_file_age_hours)
      log "MOTOR-OVERRIDE ÖREG: $engine_override (kora: ${age_hours} óra, küszöb: ${override_warn_threshold} óra) — az override Él, de fontold meg a feloldást (tools/engine-profile.sh clear)"
      today=$(date +%Y%m%d)
      if [ ! -f "$override_warn_state_file" ] || [ "$(cat "$override_warn_state_file" 2>/dev/null)" != "$today" ]; then
        printf '%s' "$today" > "$override_warn_state_file"
        notify "⚠ motor-override régi" "$engine_override (${age_hours} óra) — küszöb ${override_warn_threshold} óra" default
      fi
      engine=$engine_override
      ;;
    4)
      # INVALID — a függvény a `engine_override` üresen hagyta, de a motor
      # ténylegesen érvénytelen. A queue engine oszlopa üres lenne, ez a
      # hiba „rosszabb, mint a nem-override" — die.
      log "MOTOR-OVERRIDE: érvénytelen motor a $engine_override_file fájlban ('$evaluate_output')"
      die "érvénytelen motor-override: $evaluate_output ($engine_override_file)"
      ;;
    *)
      # 3 (no-file) nem fordulhat elő, mert a `if [ -f ... ]` őrzi az
      # ágat. Minden más státusz a függvény belső hibája — die.
      die "a motor-override kiértékelése ismeretlen státusszal tért vissza: $evaluate_status"
      ;;
  esac
fi

validate_engine "$engine" || die "ismeretlen implementer motor: $engine (auto|minimax|codex vagy a nyilvántartás neve)"
if [ "$engine" = "auto" ]; then
  [ -x "$repo_root/tools/ai-router-round.sh" ] || die "hiányzik a router adapter"
  [ -x "$repo_root/tools/model-router.py" ] || die "hiányzik a model router"
  [ -f "$repo_root/.ai/router.toml" ] || die "hiányzik a router konfiguráció"
fi

# --- 4.5 Orchestrátor-rotáció (ADR 0222/0242 D1) + reviewer-függetlenség (0138/0242 D2) ---
resume_implementer=$(resolve_branch_implementer "$round")
# MÉRT ESET 2026-08-23 (E13-R05, élesben): a kör ágán korábban a `terra`
# commitolt, ezért a D2 pin a queue `sonnet-impl` sorát felülírta `terra`-ra —
# egy olyan motorra, aminek az előfizetése elfogyott. Két kár egyszerre:
# (a) a dispatch menthetetlenül elbukott volna a terra-híváson;
# (b) az orchestrátor-pár is a pinelt motorhoz igazodik, így a kör Sonnet 5
#     `high` vezénylést kapott a szándékolt Opus 5 `max` helyett.
# A pin CÉLJA — ne keveredjenek a motorok egy körön belül — nem teljesíthető,
# ha a pinelt motor nem él; ilyenkor a queue sora lép vissza életbe, NAPLÓZVA.
# A függetlenség nem gyengül: a lentebbi feloldás a MÁR CSERÉLT motorra mér.
pinned_implementer=$resume_implementer
resume_implementer=$(resume_implementer_for "$round")
if [ -n "$pinned_implementer" ] && [ -z "$resume_implementer" ]; then
  log "FOLYTATÁS: a(z) $round ágán $pinned_implementer commitolt, de az a motor NEM futtatható (elfogyott előfizetés) — a pin elesik, a queue sora lép vissza: $engine"
fi
if [ -n "$resume_implementer" ]; then
  # ADR 0242 D2: a körhöz már tartozik távoli ág — a commitolt implementer
  # FIX (a queue `engine` oszlopát figyelmen kívül hagyjuk), a mozgatható
  # szereplő az orchestrátor.
  orchestrator=$(resolve_resume_orchestrator "$round" "$resume_implementer")
  if [ "$orchestrator" = "HALT_INDEP" ]; then
    {
      echo "round=$round"
      echo "halt=H-INDEP"
      echo "summary=A(z) $round ágán már $resume_implementer commitolt, és nincs elérhető, független orchestrátor hozzá (ADR 0242 §5.2)"
      echo "halted_at=$(date -Is)"
    } > "$halt_file"
    log "HALT (H-INDEP): folytatáskor nincs független orchestrátor a(z) $round körhöz (implementer: $resume_implementer)"
    notify "⛔ H-INDEP: $round" "folytatás — nincs független orchestrátor — emberi döntés kell" high
    exit 3
  fi
  if [ "$resume_implementer" != "$engine" ]; then
    log "FOLYTATÁS: a(z) $round ágán már $resume_implementer commitolt — az implementer fix marad (queue: $engine → $resume_implementer)"
  fi
  engine=$resume_implementer
else
  orchestrator=$(next_orchestrator "$round")
  independent_engine=$(resolve_independent_engine "$engine" "$orchestrator")
  case "$independent_engine" in
    HALT_INDEP)
      {
        echo "round=$round"
        echo "halt=H-INDEP"
        echo "summary=A kört a Terra vezényelné (rotáció vagy Claude-kvótazárlat), így a saját diffjét review-zná, és nincs elérhető, független implementer motor (a csere-motor $orch_swap_engine nem használható, MiniMax kulcs hiányzik)"
        echo "halted_at=$(date -Is)"
      } > "$halt_file"
      log "HALT (H-INDEP): nincs független reviewer a(z) $round körhöz"
      notify "⛔ H-INDEP: $round" "nincs független reviewer — emberi döntés kell" high
      exit 3
      ;;
    "$engine") : ;;
    *)
      log "REVIEWER-FÜGGETLENSÉG: a kört a Terra vezényli (review), ezért a(z) $round implementere $engine→$independent_engine"
      notify "🔀 $round: szerepcsere" "a Terra review-z, az implementer $independent_engine lett"
      engine=$independent_engine
      ;;
  esac
fi
case "$orchestrator" in terra | sol) orchestrator_preference=$orchestrator ;; esac

log "következő kör: $round · orchestrátor=$orchestrator · implementer=$engine · brief=$brief · ADR=$adr"

if [ "$dry_run" = "1" ]; then
  log "--dry-run: itt indulna az orchestrátor-session, de nem indul"
  exit 0
fi

# A rotáció állapota KÖRÖNKÉNT kulcsolt (ADR 0242 D1): a fenti
# next_orchestrator()/resolve_resume_orchestrator() már a kör ELSŐ dispatchje
# ELŐTT rögzítette az orchestrátort (orch_round_dir/$round), és a globális
# orch_last_file-t is CSAK akkor léptette. Egy elhalt kör újraindítása így
# ugyanazt a motort kapja vissza — nincs itt már mit írni.

# A kör bejegyzése a futók közé. A takarítás EXIT-trapre megy, mert a driver
# sok ágon lép ki (halt, hiba, merge) — a maradék bejegyzés különben örökre
# blokkolna egy slotot (a stale maradék MÉRT hibaosztály, memória 2026-08-04).
active_inflight="$round"
trap 'inflight_remove "$active_inflight"' EXIT
inflight_add "$round" "$brief"

brief_lint_report=$(write_brief_lint "$round" "$brief")
resume_state_report=$(write_resume_state "$round")

# Kimaradás-mód (2026-08-06): ha a GitHub Actions incidensben van, a CI-evidencia
# NEM megszerezhető. Ilyenkor a kör ne várjon órákig egy sosem induló futásra —
# a merge-kapu a LOKÁLISAN futtatott, UGYANAZ a mérce-lánc.
ci_note="nincs"
if github_actions_degraded; then
  ci_note="$state_dir/ci-note-$round.md"
  cat > "$ci_note" <<'CINOTE'
## ⚠ KIMARADÁS-MÓD — a CI-evidencia most nem szerezhető meg

A GitHub Actions **incidensben van** (a lánc a hivatalos státusz-komponensből
mérte). A futások vagy el sem indulnak, vagy órákig `queued` állapotban ragadnak.
NE várj `gh run watch`-csal, és NE dispatch-elj újra és újra.

**A merge-kapu ilyenkor a LOKÁLISAN lefuttatott, UGYANAZ a mérce-lánc** — nem
kevesebb, csak lassabb (a boxon ~20 perc a CI ~9 perce helyett):

```bash
tools/round-gate.sh <a brief §7 útvonalai>
$HOME/flutter/bin/flutter test
PROPERTY_SEED=$(date +%s) $HOME/flutter/bin/flutter test test/property
$HOME/flutter/bin/dart run tool/ci/check_assets.dart
$HOME/flutter/bin/dart run tool/ci/check_song_schema.dart
$HOME/flutter/bin/dart run tool/ci/check_song_fixture_licenses.dart
```

Kötelező (különben a merge bizonyítatlan):

1. mind a hat parancs kimenetét (csonkítatlanul, kilépési kóddal) idézd a PR
   törzsébe „lokális teljes mérce — GitHub Actions incidens" cím alatt, a
   `git rev-parse HEAD` SHA-val együtt;
2. a PR törzsébe írd bele, hogy a CI-evidencia a helyreállás UTÁN pótlandó
   (`gh workflow run` a merge SHA-jára), és nyiss rá follow-up sort a HANDOFF-ban;
3. **natív/release-érintő diffnél (APK-ág) NINCS lokális pótlás** — ott a kör
   `blocked` jelzéssel álljon meg, mert a boxon nincs Android SDK.
CINOTE
  log "KIMARADÁS-MÓD: a $round merge-kapuja a lokális teljes mérce ($ci_note)"
fi

# --- 5. Az orchestrátor-prompt összeállítása ------------------------------
run_stamp=$(date +%Y%m%dT%H%M%S)
prompt_file="$state_dir/prompt-$round-$run_stamp.md"
session_log="$state_dir/session-$round-$run_stamp.log"

sed -e "s|{{ROUND}}|$round|g" \
    -e "s|{{BRIEF}}|$brief|g" \
    -e "s|{{ENGINE}}|$engine|g" \
    -e "s|{{ADR}}|$adr|g" \
    -e "s|{{BRIEF_LINT}}|$brief_lint_report|g" \
    -e "s|{{RESUME_STATE}}|$resume_state_report|g" \
    -e "s|{{CI_NOTE}}|$ci_note|g" \
    -e "s|{{STATUS_FILE}}|$status_file|g" \
    -e "s|{{ROUTER_STATUS_FILE}}|$router_status_file|g" \
    -e "s|{{HALT_FILE}}|$halt_file|g" \
    "$prompt_template" > "$prompt_file"

# --- 6. Friss headless orchestrátor-session -------------------------------
rm -f "$status_file" "$router_status_file"
log "orchestrátor-session indul ($round), időkorlát ${session_timeout}s → $session_log"
notify "▶ $round indul" "motor=$engine · ADR=$adr · friss orchestrátor-session"

# Az orchestrátor INTERAKTÍV claude sessionként fut egy tmux-ban (user-döntés
# 2026-07-31), mert a -p és a --bg mód sehol nem látszott. A telefonos
# láthatóság feltétele viszont NEM az interaktivitás önmagában, hanem a
# `$pipeline_claude_config_dir` (lásd ott a mérést): a session-regiszternek a
# híd config-dirjébe kell kerülnie. A bootstrap-prompt rövid fájl-hivatkozás
# (az argv-önillesztés — L12 — kizárva).
session_exit=0
run_orchestrator_session "pipeline-$round" "$prompt_file" "$session_log" \
  "$status_file" "$session_timeout" "$round" \
  "$(orch_pair_model "$engine")" "$(orch_pair_effort "$engine")" || session_exit=124


# --- 7. Kimenet osztályozása ----------------------------------------------
# A session KÖTELESSÉGE megírni a $status_file-t. Ha nincs, a jelentését NEM
# fogadjuk el bemondásra — ez ugyanaz a szabály, mint az implementer-oldalon
# (AGENTS.md §15.2): jelzés nélküli futás = bukott futás.
if [ ! -f "$status_file" ] && claude_quota_hold_if_detected "$round" "$session_log"; then
  # A session a Claude-kereten halt meg, nem a repón: NINCS HALT-fájl, nincs
  # önjavító kör. A hold lejártáig a firing-ok kilépnek, utána a kör újra
  # sorra kerül — pontosan az a viselkedés, amit a Terra/Codex holdok adnak.
  git checkout -q main 2>/dev/null || true
  log "KVÓTA: a(z) $round orchestrátor-sessionje a Claude-kereten halt meg — nincs HALT, a lánc a reset után folytatja"
  notify "⏳ Claude-kvóta: $round" "a kör a keret-reset után automatikusan újraindul" high
  exit 0
fi
if [ ! -f "$status_file" ]; then
  {
    echo "round=$round"
    echo "halt=H-NOSIGNAL"
    echo "summary=az orchestrátor-session jelzés nélkül ért véget (exit $session_exit)"
    echo "session_log=$session_log"
    echo "halted_at=$(date -Is)"
  } > "$halt_file"
  git checkout -q main 2>/dev/null || true
  log "HALT: nincs kör-jelzés — $halt_file (az önjavítás a következő firingen indul)"
  notify "⛔ HALT: $round" "az orchestrátor-session jelzés nélkül ért véget — önjavítás indul" high
  exit 5
fi

outcome=$(grep -m1 '^outcome=' "$status_file" | cut -d= -f2-)
summary=$(grep -m1 '^summary=' "$status_file" | cut -d= -f2-)

case "$outcome" in
  merged)
    log "$round MERGE-ELVE — $summary"
    notify "✅ $round merge-elve" "$summary"
    git fetch -q origin main && git reset -q --hard origin/main
    # D2 fail-safe (E99-R19): az orchesztrátor a záró `docs(handoff…)`
    # commitba teszi a sor `pending → done` átírást (lásd
    # pipeline-orchestrator-prompt.md §5). Ha a fetch már behozza azt a
    # commitot, a `sed` no-op, nincs `chore(pipeline)` commit és nincs extra
    # push/CI. Ha viszont a sor a fetch után is `pending` maradt (az
    # orchesztrátor kihagyta a lépést), EZ az ág pótolja — az elveszett
    # `done` státusz mért hibaosztály, a fail-safe zártan tartja.
    sed -i "s|^\($round\t.*\t\)pending$|\1done|" "$queue_file"
    # A completion-riport §3 matrixa a queue-ból SZÁRMAZTATOTT (E15-R09 H5
    # önjavító kör, ADR 0112, 2026-09-03). A `program_completion_test.dart` A1
    # cellája SZIGORÚ egyenlőséget mér a queue ellen, ezért minden `done`-ra
    # billentett sor elavulttá teszi a matrixot — és a lánc nem indul piros
    # main fölé, tehát a drift a KÖVETKEZŐ kört is megállítja. MÉRVE: az
    # E15-R08 merge (`e9691f74`) 89 percre megállította a láncot (main Full
    # Gate run 33704424852, 2 piros cella). A szinkron idempotens: ha az
    # orchesztrátor záró commitja már elvégezte, ez no-op.
    # A szinkron KIZÁRÓLAG a valódi repó-queue ellen fut: egy tesztből
    # felüldefiniált `PIPELINE_QUEUE_FILE` mellett a riport (ami mindig a
    # repóé) hamis számokat kapna.
    sync_paths=("$queue_file")
    if [ "$queue_file" = "$repo_root/docs/execution/pipeline-queue.tsv" ] \
       && [ -x "$repo_root/tools/sync-completion-matrix.py" ] && [ -f "$completion_report_file" ]; then
      if "$repo_root/tools/sync-completion-matrix.py" --write \
           --queue "$queue_file" --report "$completion_report_file" >/dev/null 2>&1; then
        sync_paths+=("$completion_report_file")
      else
        log "FIGYELEM: a completion-matrix szinkron hibára futott — a main gate pirosra válthat"
      fi
    fi
    if [ -n "$(git status --porcelain -- "${sync_paths[@]}")" ]; then
      git add -- "${sync_paths[@]}"
      git commit -q -m "chore(pipeline): $round done — fail-safe (ADR 0087, D2 E99-R19)"
      git push -q origin main || log "FIGYELEM: a sor-fájl push-a nem ment át"
    fi
    inflight_remove "$round"
    active_inflight=""
    # A main mérése a merge UTÁN indul, és a következő körrel PÁRHUZAMOSAN fut:
    # nem lassítja a láncot, viszont az öröklött piros gate a következő kör
    # ELŐTT derül ki, nem annak a merge-kapujánál (ADR 0174).
    # Tudás-index frissítés (ADR 0312): a MEGOSZTOTT igazság a `main`, ezért a
    # frissítés horgonya a merge — nem fájlfigyelő. Egy kör-ág köztes mentései
    # nem a közös tudás, viszont minden merge azonnal elavulttá teszi az
    # indexet, és az elavult index a legrosszabb: magabiztos, de régi választ ad.
    # Inkrementális (csak a változott chunk), leválasztva, sosem blokkol.
    if [ "${PIPELINE_RAG_REINDEX:-1}" = "1" ] && [ -f "$HOME/.rag-openai.env" ] \
       && [ -f "$repo_root/tools/knowledge-rag.mjs" ] && command -v node >/dev/null 2>&1; then
      setsid nohup node "$repo_root/tools/knowledge-rag.mjs" --reindex \
        >> "$state_dir/rag-reindex.log" 2>&1 &
      log "tudás-index: inkrementális újraindexelés indítva (ADR 0312)"
    fi

    if [ "${PIPELINE_MAIN_HEALTH:-1}" = "1" ]; then
      if gh workflow run full-gate.yml --ref main >/dev/null 2>&1; then
        log "main-egészség: full-gate dispatch-elve a main-re"
      else
        log "figyelem: a main-egészség full-gate dispatch nem ment át"
      fi
    fi
    log "a lánc mehet tovább"
    spawn_next_firing
    exit 0
    ;;
  halted)
    git checkout -q main 2>/dev/null || log "figyelem: a munkafa nem tért vissza mainre"
    handle_round_halt "$round" "$status_file" "$session_log"
    exit 3
    ;;
  *)
    {
      echo "round=$round"
      echo "halt=H-BADSIGNAL"
      echo "summary=ismeretlen outcome a kör-jelzésben: '$outcome'"
      echo "session_log=$session_log"
      echo "halted_at=$(date -Is)"
    } > "$halt_file"
    log "HALT: értelmezhetetlen kör-jelzés ('$outcome')"
    notify "⛔ HALT: $round" "értelmezhetetlen kör-jelzés: '$outcome'" high
    exit 5
    ;;
esac
