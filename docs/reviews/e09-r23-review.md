# E09-R23 — Review

Brief: docs/rounds/e09-r23-leaderboards-and-opt-in-competition.md
ADR: docs/adr/0418-leaderboards-and-opt-in-competition.md
Diff: `git diff origin/main...minimax/e09-r23-leaderboards-and-opt-in-competition`
Reviewer: Claude Sonnet 5 (orchestrátor) + `security-reviewer` subagent (risk=high) · Dátum: 2026-08-24
Verdikt: CHANGES REQUIRED (1 MINOR)

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 1 · NOTE: 2

Gate-újrafuttatás SAJÁT kézzel, izolált klónban (`/tmp/review-e09-r23`,
HEAD `1d4bb87d`): **minden gate zöld** (format, analyze, célzott Flutter-teszt,
architecture, secrets, l10n, backend ruff format+check, TELJES backend pytest
— 646 teszt, 0 hiba). A `security-reviewer` subagent (párhuzamos, `/tmp/
security-review-e09-r23`) SAJÁT mutation-próbákkal (nem az implementer
tesztkészletére hagyatkozva) ellenőrizte az A1/A3/A4/A6 invariánsokat és a
scope-ot — mindegyik ÁLLTA a próbát, ld. lent.

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
- **Státusz:** OPEN — javító kör dispatch-elve.

### F2 — NOTE — Router docstring elavult szóhasználat

- **Fájl:** `backend/app/community/routers/leaderboards.py:20`
- **Probléma:** a docstring `"preferred_in"/"preferred_out"` választ ígér, a
  `set_opt_in` ténylegesen `"opted_in"/"opted_out"`-ot ad vissza.
- **Hatás:** kozmetikai, nincs futásidejű hatás.
- **Javítás:** a docstring frissítése a tényleges értékekre (a javító körrel
  egyszerre elvégezhető, nem növeli érdemben a diffet).
- **Státusz:** OPEN — javító körben javasolt, nem blokkol.

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
| backend pytest (teljes, 646 teszt) | zöld | ✅ |
| CI (teljes suite + property + APK) | — | dispatch a fix-kör után |

## Merge-döntés

Az ADR 0052 szerint: nyitott MINOR (F1) van, tehát a javító kör a lánc NORMÁL
útja (user-döntés 2026-07-31) — MiniMax M3 dispatch-elve a leletlistával
(F1 + F2). Merge csak a javítás + friss gate + CI zöld UTÁN.
