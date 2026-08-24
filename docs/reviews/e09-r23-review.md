# E09-R23 — Review

Brief: docs/rounds/e09-r23-leaderboards-and-opt-in-competition.md
ADR: docs/adr/0418-leaderboards-and-opt-in-competition.md
Diff: `git diff origin/main...minimax/e09-r23-leaderboards-and-opt-in-competition`
Reviewer: Claude Sonnet 5 (orchestrátor) + `security-reviewer` subagent (risk=high) · Dátum: 2026-08-24
Verdikt: **APPROVED** (javító kör után, `c4edb7b1`)

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 1 (ZÁRVA `c4edb7b1`) · NOTE: 2 (F2 ZÁRVA, F3 nem blokkoló megfigyelés)

Gate-újrafuttatás SAJÁT kézzel, izolált klónban (`/tmp/review-e09-r23`,
HEAD `1d4bb87d`): **minden gate zöld** (format, analyze, célzott Flutter-teszt,
architecture, secrets, l10n, backend ruff format+check, TELJES backend pytest
— 646 teszt, 0 hiba). A `security-reviewer` subagent (párhuzamos, `/tmp/
security-review-e09-r23`) SAJÁT mutation-próbákkal (nem az implementer
tesztkészletére hagyatkozva) ellenőrizte az A1/A3/A4/A6 invariánsokat és a
scope-ot — mindegyik ÁLLTA a próbát, ld. lent.

## Javító kör (`c4edb7b1`) — F1/F2 zárása

**F1 zárva.** `_build_base_query` egy `include_self: bool = False` paramétert
kapott — `get_own_rank` mindkét lekérdezésén (a sor-keresés ÉS a rank-számláló
query) `include_self=True`-val hívja, ami a follow-EXISTS feltételt egy
`OR CommunityProfile.id = viewer_profile_internal_id` ággal bővíti. A publikus
lap-lekérdezés (`get_leaderboard_page`) VÁLTOZATLANUL `include_self` nélkül fut
— az A4 invariáns ott nem sérül. **Reviewer saját valódi-sértés próbája:** a
fix ELŐTTI (`1d4bb87d`) service-fájlt visszahelyeztem egy izolált klónba, az ÚJ
`test_own_rank_friends_challenge_returns_self_even_without_self_follow` teszt
PIROSAT adott (`FAILED`), majd a fix visszaállítása után ZÖLD — a teszt
TÉNYLEG méri a hibát, nem véletlenül zöld. A régi
`test_own_rank_returns_null_when_opted_out` (opt-out eset) VÁLTOZATLANUL zöld
maradt — a fix nem tágította a láthatóságot máshol.

**F2 zárva.** A `leaderboards.py` docstring `"preferred_in"/"preferred_out"` →
`"opted_in"/"opted_out"`-ra javítva, egyezik a `set_opt_in` tényleges
visszatérési értékével.

**Gate újrafuttatva SAJÁT kézzel, MÁSODIK izolált klónban**
(`/tmp/review-e09-r23-fix1`, HEAD `c4edb7b1`): minden gate zöld (format,
analyze, célzott Flutter-teszt, architecture, secrets, l10n, backend ruff
format+check, TELJES backend pytest — 647 teszt, 0 hiba, 13/13 zöld a
`test_leaderboard_service.py`-ban). Scope-audit `--base c8c0a3fa` (a review-
commit utáni bázis) → **OK**, 4 changed path.

**Folyamat-jegyzet (nem érinti a kód-verdiktet):** az első javító-kör dispatch
egy MELLÉKESEN, a munkapéldány SAJÁT git fájába helyezett leletlista-fájl
(`.pipeline-findings-E09-R23.md`, az orchestrátor saját hibája, NEM az
implementeré) miatt hamis `scope_audit=VIOLATION`/`stopped` jelzést kapott — a
fájl eltávolítása után a scope-audit tisztán `OK`-t adott, az implementer
tényleges commitja (`c4edb7b1`) mindvégig csak a 4 releváns fájlt érintette.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | Csak verified eredmény kerül a leaderboardra | ✅ | `test_a1_only_verified_results_appear` + `test_a1_probe_drops_verified_filter_pending_row_would_appear` (valódi-sértés próba, §6.1 kötelező); reviewer SAJÁT próbája (WHERE-filter eltávolítva) is PIROSAT adott, majd zöld visszaállítva |
| A2 | Tie-breaker sorrend dokumentált és determinisztikus | ✅ | `test_a2_deterministic_tie_break_by_submitted_at_then_id` + `test_a2_tie_break_stable_across_calls` (`metric_value DESC, submitted_at ASC, id ASC`, ADR 0418 D4) |
| A3 | Opt-out felhasználó nem jelenik meg public scope-ban | ✅ | `test_a3_opt_out_profile_excluded_from_leaderboard` + `test_a3_set_opt_in_toggle_idempotent`; reviewer SAJÁT próbája: az `opt_in_exists` EXISTS-alfeltétel eltávolítása PIROSAT adott — a szűrő MINDEN challenge-típusra egységesen, feltétel nélkül fut (`leaderboard_service.py:267-271`), nincs típus-specifikus kikerülés |
| A4 | Friends-scope csak a follow-gráf alapján látható userek eredményét mutatja | ✅ | `test_a4_friends_scope_filters_by_viewer_follows` + `test_a4_non_friends_scope_has_no_follow_filter`; reviewer SAJÁT próbája: follower/followed felcserélve PIROSAT adott — az irány helyes (viewer követi az entry tulajdonosát) |
| A5 | Pagination stabil, nincs duplikált sor | ✅ | `test_a5_pagination_stable_no_duplicates` (base64 JSON cursor, `(metric_value, submitted_at, id)` szigorú predikátum) |
| A6 | Disqualification/delete után determinisztikus projekció-frissítés | ✅ | `test_a6_disqualification_deletes_entry_deterministically` (verification_state → rejected) + `test_a6_row_deletion_removes_entry_deterministically` (DELETE) — teszt-szintű DB-mutáció, ADR 0418 D5, nincs admin endpoint; a projekció query-time (nincs materializált tábla, `models/leaderboard.py` csak `community_leaderboard_opt_ins`-t ad), tehát minden olvasás friss |
| A7 | Nagy szövegméret mellett a rank-sor érthetően felolvasható (accessibility) | ✅ | `leaderboard_screen_test.dart`: egy bundled `Semantics` node rank-soronként, verified-badge külön szemantikus label, 2× text-scale próba |

## Scope-audit

`python3 tools/scope-audit.py --repo /tmp/review-e09-r23 --brief docs/rounds/e09-r23-leaderboards-and-opt-in-competition.md --base 5883c79b`
→ **OK** (10 changed path(s), 0 generated/ignored) — a bázis a pre-flight
utolsó (self-heal) commitja, nem a kör-előtti `main`, mert az ADR 0418
`allowed_paths`-bővítése (`challenge_repository.dart`/`_impl.dart`) az én
saját pre-flight-artefaktumom, nem az implementer diffje. A
`security-reviewer` subagent függetlenül megismételte, ugyanaz az eredmény.

## Megállapítások

### F1 — MINOR — `get_own_rank` self-lookup a `friends` típusú challenge-nél tévesen alkalmazza a follow-gráf szűrőt önmagára

- **Fájl:** `backend/app/community/services/leaderboard_service.py:530-535`
- **Probléma:** a `get_own_rank` a `_build_base_query`-t `friends_scope=True`-val
  hívja meg egy `friends` típusú challenge-nél is a SAJÁT sor kereséséhez — a
  follow-szűrő így `follower_profile_id = viewer AND followed_profile_id =
  <viewer saját profile.id-je>`-t vár, azaz megköveteli, hogy a viewer
  KÖVESSE ÖNMAGÁT. Egy legitim, opt-in, verified résztvevő saját helyezése
  emiatt mindig `None`.
- **Hatás:** a §5.4/D6 "saját rank endpoint" `friends` típusú challenge-nél
  funkcionálisan törött (mindig üres választ ad egy létező résztvevőnek is).
  **Fail-closed, NEM privacy-sérülés** — nem szivárogtat adatot, csak
  alul-mutat. A Flutter oldal ezt a körben NEM köti be (ADR 0418 D6), tehát
  felhasználó ma nem látja — de a backend endpoint, ahogy van, hibás.
- **Kötelező javítás:** a self-lookup ágon a follow-szűrőt ki kell hagyni
  (a viewer mindig látja a SAJÁT sorát, függetlenül attól, hogy a
  `friends`-scope szűrő máshol mit enged át) — pl. külön branch
  `get_own_rank`-ban, vagy a `_build_base_query` egy `include_self`
  paraméterrel.
- **Ellenőrzés:** egy ÚJ teszt-eset (`friends` típusú challenge, opt-in,
  verified résztvevő, `get_own_rank` a résztvevő saját public_id-jével hívva)
  a javítás ELŐTT PIROS, utána ZÖLD.
- **Státusz:** **FIXED** (`c4edb7b1`) — reviewer saját visszasértés-próbával megerősítve.

### F2 — NOTE — Router docstring elavult szóhasználat

- **Fájl:** `backend/app/community/routers/leaderboards.py:20`
- **Probléma:** a docstring `"preferred_in"/"preferred_out"` választ ígér, a
  `set_opt_in` ténylegesen `"opted_in"/"opted_out"`-ot ad vissza.
- **Hatás:** kozmetikai, nincs futásidejű hatás.
- **Javítás:** a docstring frissítése a tényleges értékekre (a javító körrel
  egyszerre elvégezhető, nem növeli érdemben a diffet).
- **Státusz:** **FIXED** (`c4edb7b1`).

### F3 — NOTE — Nem-`friends` scope-ok teljes opt-in halmaza mindenki számára olvasható

- **Fájl:** `backend/app/community/services/leaderboard_service.py` (scope-ág)
- **Megfigyelés:** `club`/`dailyCommunity`/`periodicGlobal`/`personalBest`
  típusú challenge leaderboardját bármely hitelesített profil lekérdezheti
  (a teljes opt-in, verified halmazt) — ez SZÁNDÉKOS az ADR 0418 D4 szerint
  (a globális/napi táblák design szerint publikusak az opt-in halmazon
  belül), de a `club`-tagság ellenőrzésének hiánya (Kör 24 függőség) egy
  jövőbeli kör felülvizsgálati pontja.
- **Hatás:** nem blokkol, nem privacy-sérülés a jelenlegi kör-scope alatt.
- **Státusz:** nem blokkol — jövőbeli (Kör 24) felülvizsgálatra jegyezve.

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény | Ellenőrizve |
|---|---|---|
| format | zöld | ✅ (saját futtatás, `/tmp/review-e09-r23`) |
| analyze | zöld | ✅ |
| célzott teszt (`leaderboard_screen_test.dart`) | zöld, 6/6 | ✅ |
| architecture | zöld | ✅ |
| secrets | zöld (3586 fájl) | ✅ |
| l10n | zöld | ✅ |
| backend ruff format+check | zöld | ✅ |
| backend pytest (teljes, 646→647 teszt a javító kör után) | zöld | ✅ |
| CI (teljes suite + property + APK) | — | dispatch review után, merge előtt |

## Merge-döntés

Az ADR 0052 szerint: minden gate zöld ÉS nincs nyitott BLOCKER/MAJOR/MINOR →
merge. F1 és F2 zárva (`c4edb7b1`), reviewer saját kézzel megerősítve két
izolált klónban. CI-dispatch az exact-SHA `c4edb7b1`-en következik; merge
csak a CI zöld futása UTÁN.
