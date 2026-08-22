# E09-R23 — Leaderboards és opt-in versenynézet

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ db6293f4`)
- **Típus:** Chapter 10 (Epic 9 — Community Platform), Kör 23
- **Kör-azonosító:** `E09-R23`
- **Branch:** `<motor>/e09-r23-leaderboards-and-opt-in-competition`
- **Előfeltétel:** `E09-R22` merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0412` — a szám FOGLALT (Epic 9 batch-tartomány 0395-0419). Az ADR-t a Claude írja meg a kör indítási pre-flightjában a §5 döntéseiből; az implementer a `docs/adr/`-t NEM érinti (TILOS zóna).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a Kör 22 `challenge_result.verification_state` TÉNYLEGES értékkészletét — a projekció kizárólag a `verified` értékű sorokat olvassa. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "backend/app/community/services/leaderboard_service.py",
  "backend/app/community/models/leaderboard.py",
  "backend/app/community/routers/leaderboards.py",
  "backend/alembic/versions/e09_r23_0017_community_leaderboard.py",
  "lib/features/community/presentation/screens/leaderboard_screen.dart",
  "backend/tests/community/test_leaderboard_service.py",
  "test/features/community/presentation/leaderboard_screen_test.dart",
  "docs/rounds/e09-r23-leaderboards-and-opt-in-competition.md",
]
gate_tests = [
  "test/features/community/presentation/leaderboard_screen_test.dart"
]
native_gate = false
```

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. **Listán kívüli fájl kellene → `stopped`**,
és a kimenet a brief-revízió kérése, nem az `allowed_paths` csendes tágítása.
Meglévő, ma zöld teszt elbukása → `blocked`, nem a teszt átírása.

## 1. Cél

Verified, összehasonlítható és privacy-kompatibilis challenge-ranglista — opt-in, nincs all-time total XP globális lista.

## 2. Jelenlegi állapot — mért tények

- A Kör 22 `challenge_result` MA hordozza a `verification_state`-et — ez a kör az első fogyasztója, kizárólag `verified` sorokra szűrve
- A Kör 4 privacy-policy MA rendelkezik `leaderboard opt-in` mezővel a privacy-settingsben (a §9.2 SDD szerint alapból kikapcsolt)

## 3. Scope

**Benne van:** leaderboard projekció KIZÁRÓLAG verified resultból · metric-direction, tie-breaker, cohort, difficulty-band dokumentálva · friends, club, challenge-global scope; NINCS all-time total XP global lista · a felhasználó explicit opt-in nélkül nem jelenik meg public scope-ban · saját rank endpoint + cursor pagination · Flutter leaderboard accessible rank sorral, verified-badge magyarázattal · disqualification/delete után determinisztikus projekció-frissítés.

**NINCS benne (tilos):**

- Bármilyen all-time, összesített XP-alapú globális ranglista.
- A verification-logika módosítása (Kör 22 lezárt szerződése).
- `docs/adr/**` — az ADR 0412-t a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `backend/app/community/services/leaderboard_service.py` | ÚJ |
| `backend/app/community/models/leaderboard.py` | ÚJ |
| `backend/app/community/routers/leaderboards.py` | ÚJ |
| `backend/alembic/versions/e09_r23_0017_community_leaderboard.py` | ÚJ |
| `lib/features/community/presentation/screens/leaderboard_screen.dart` | ÚJ |
| `backend/tests/community/test_leaderboard_service.py` | ÚJ — a §6 cellái |
| `test/features/community/presentation/leaderboard_screen_test.dart` | ÚJ |

**Tilos zóna:** `backend/app/community/services/challenge_verification_service.py` (csak olvasás) · `docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések (ADR 0412)

### 5.1 A leaderboard KIZÁRÓLAG `verified` eredményből épül

A projekció WHERE-feltétele explicit `verification_state = 'verified'` — `pending`/`unverified`/`rejected` sorok soha nem kerülnek a rangsorba.

**NEM elfogadható gyengítés:** egy "jóhiszemű" projekció, ami pending eredményt is beleszámol "amíg a verification lefut" — ez pontosan a nem-ellenőrzött lokális XP globális megjelenését engedné meg.

### 5.2 NINCS all-time total XP globális lista

Minden leaderboard egy KONKRÉT challenge-hez vagy egy dokumentált időszakos ablakhoz kötött — sosem egy örökös, összesített XP-rangsor.

### 5.3 A megjelenés EXPLICIT opt-in

A felhasználó alapból NEM jelenik meg public scope-ban; a megjelenéshez a Kör 4 privacy-settingsben explicit bekapcsolás szükséges.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Csak verified eredmény kerül a leaderboardra | `test_leaderboard_service.py` |
| A2 | Tie-breaker sorrend dokumentált és determinisztikus | `test_leaderboard_service.py` |
| A3 | Opt-out felhasználó nem jelenik meg public scope-ban | `test_leaderboard_service.py` |
| A4 | Friends-scope csak a follow-gráf alapján látható userek eredményét mutatja | `test_leaderboard_service.py` |
| A5 | Pagination stabil, nincs duplikált sor | `test_leaderboard_service.py` |
| A6 | Disqualification/delete után determinisztikus projekció-frissítés | `test_leaderboard_service.py` |
| A7 | Nagy szövegméret mellett a rank-sor érthetően felolvasható (accessibility) | `leaderboard_screen_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A projekció `pending` sorokat is beleszámol | A1 |
| Egy opt-out user mégis megjelenik a public leaderboardon | A3 |
| A tie-breaker nem determinisztikus (pl. sorrend a lekérdezési sorrendtől függ) | A2 |
| Egy diszkvalifikált eredmény a régi helyezésen marad a frissítés után | A6 |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** vedd ki a `verification_state = 'verified'` szűrőt a projekció queryjéből, futtasd a backend pytest-et egy pending eredménnyel → az **A1** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/community/presentation/leaderboard_screen_test.dart
```

A backend oldal külön, önálló parancs (NEM láncolva):

```bash
cd backend && python -m pytest tests/community/test_leaderboard_service.py -q
```

A gate artefaktum a mérce (`tools/round-gate.sh`) — a parancssorban
reprodukált parancslista NEM bizonyíték (AGENTS.md §12, L09). A script
`format` → `analyze` → `test <minden útvonal külön>` → `architecture`
lépéseket KÜLÖN processzként futtat, csonkítatlan kimenettel. **Tilos**
bármilyen szűrés vagy kézi lánc a promptban (OOM, L05). A kötelező gate-et
**TILOS háttérbe küldeni** (`run_in_background`) — az egy-fordulós harness a
forduló végén megöli, mielőtt eredmény érkezne (L183/L254). CI-dispatch, PR és
merge mindig Claude-oldal: az implementer `gh`-t NEM hív.

## 8. Implementációs sorrend

1. `leaderboard.py` — a projekció-modell (scope, metric, tie-breaker, cohort).
2. `leaderboard_service.py` — kizárólag verified forrásból építő query, opt-in ellenőrzés.
3. `leaderboards.py` router — friends/club/challenge-global scope, saját-rank endpoint, cursor pagination.
4. `leaderboard_screen.dart` — accessible rank-sor, verified-badge.
5. A disqualification/delete utáni determinisztikus újraépítés tesztje.
6. A valódi-sértés próba §10-be; a §7 mindkét parancsa KÜLÖN futtatva.

## 9. Kockázatok

- **A pending eredmény beszámítása "UX-gyorsításként".** Ez épp azt az invariánst sértené, amit a Kör 22 megalapozott (A1).
- **Az opt-out megkerülése.** Egy elfelejtett ellenőrzési pont a public scope-ban szivárogtatná a privát adatot (A3).
- **Az all-time XP-lista visszacsúszása.** Csábító "funkció", de a §15.6 SDD kifejezetten kizárja az első verzióból.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
