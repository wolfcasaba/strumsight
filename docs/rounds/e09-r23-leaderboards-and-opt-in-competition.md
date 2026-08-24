# E09-R23 — Leaderboards és opt-in versenynézet

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ db6293f4`) — **pre-flight §0.0-val kiegészítve 2026-08-24**
- **Típus:** Chapter 10 (Epic 9 — Community Platform), Kör 23
- **Kör-azonosító:** `E09-R23`
- **Branch:** `<motor>/e09-r23-leaderboards-and-opt-in-competition`
- **Előfeltétel:** `E09-R22` merge-elve
- **Brief szerzője:** Claude (Opus 5); §0.0 pre-flight-revízió: Claude Sonnet 5
- **ADR:** ~~`0412`~~ **`0418`** — a `0412` MÁR foglalt volt
  (`docs/adr/0412-media-processing-privacy-and-moderation-state.md`),
  `tools/round-slots.py reserve-adr --round E09-R23` friss számot adott. Lásd
  [ADR 0418](../adr/0418-leaderboards-and-opt-in-competition.md) — a teljes
  mért kontextus, a D1–D6 döntések és az elutasított alternatívák ott vannak,
  ez a szakasz csak a brief-lokális következményeket sorolja.

## 0.0 Pre-flight brief-revízió (2026-08-24, Claude Sonnet 5) — OLVASD EL ADR 0418 ELŐTT/HELYETT

A brief eredeti szövege (1–11. szakasz, lent, VÁLTOZATLANUL hagyva
történeti okból) HÁROM ponton méretlen feltevésre épült. A mért tényeket és
a döntéseket [ADR 0418](../adr/0418-leaderboards-and-opt-in-competition.md)
hordozza; itt csak az összefoglaló és az `allowed_paths` tényleges,
ÉRVÉNYES alakja:

1. **`allowed_paths` bővítve 2 MÁR létező fájllal** — a
   `challenge_repository_impl.dart` docstringje explicit "Kör 23 scope"-nak
   jelöli a `leaderboard()` bekötését (ugyanaz a hibaosztály, mint az
   E09-R22 pre-flight `challenges.py`/`challenge_repository_impl.dart`
   bővítése). A `leaderboard()` metódus SZIGNATÚRÁJA fagyott marad (ADR
   0418 D1) — csak a teste és egy ÚJ, kolokált `LeaderboardEntry` osztály
   kerül a `challenge_repository.dart`-ba.
2. **A brief §2 "Kör 4 leaderboard opt-in mező MA létezik" állítása TÉVES**
   (mérve: 0 találat a teljes fában) — az opt-in állapot egy ÚJ, önálló
   `community_leaderboard_opt_ins` táblában él, amit a MÁR allowed
   `models/leaderboard.py` + a kör saját migrációja épít fel. A Kör 4
   `community_privacy_settings`/`profile.py` NEM módosul (ADR 0418 D2).
3. **A §6 A6 "disqualification/delete" nem elérhető input** (`verified`
   terminális állapot a tilos-zóna service-ben, profil hard-delete nem
   létezik) — az A6 cella teszt-szintű DB-mutációval szimulálja a hatást,
   nem admin-endpointtal (ADR 0418 D5).

Emellett a §5 "kötött architekturális döntések" alá az ADR 0418 D3/D4/D6
három TOVÁBBI, mért döntést ad (metric-direction, tie-breaker/scope, router
API-alak) — ezek NEM ütköznek az eredeti §5.1–§5.3-mal, csak kiegészítik.

**Az ÉRVÉNYES `ai-router` blokk (a §5 alattinak MEGFELELŐEN, a lenti eredeti
felülírva):**

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "backend/app/community/services/leaderboard_service.py",
  "backend/app/community/models/leaderboard.py",
  "backend/app/community/routers/leaderboards.py",
  "backend/alembic/versions/e09_r23_0017_community_leaderboard.py",
  "lib/features/community/domain/repositories/challenge_repository.dart",
  "lib/features/community/data/repositories/challenge_repository_impl.dart",
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

**Kockázat = high, indoklás:** privacy-érzékeny felület (opt-in láthatóság +
follow-graph-alapú szűrés egy versenynézetben) — az A3/D2 pontosan ezt
érinti, nem egy `allowed_paths` string-egyezés (brief-lint S7 lelet zárva).

---

## Eredeti brief szövege (1–11. szakasz, történeti — a §0.0/ADR 0418 felülírja, ahol eltér)

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a Kör 22 `challenge_result.verification_state` TÉNYLEGES értékkészletét — a projekció kizárólag a `verified` értékű sorokat olvassa. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.
>
> **Mérve (§0.0): `verified` a pontos, tényleges wire-string**
> (`backend/app/community/models/challenge_result.py:73`,
> `CHALLENGE_RESULT_STATE_VERIFIED = "verified"`) — a brief eredeti szövege
> ezen a ponton PONTOS volt, nincs eltérés.

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
**(A fenti blokk ELAVULT — ld. a §0.0 ÉRVÉNYES blokkját fent.)**

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

- A Kör 22 `challenge_result` MA hordozza a `verification_state`-et — ez a kör az első fogyasztója, kizárólag `verified` sorokra szűrve (mérve, pontos: `verified`).
- ~~A Kör 4 privacy-policy MA rendelkezik `leaderboard opt-in` mezővel~~ — **TÉVES, ld. §0.0/ADR 0418 Kontextus 2.** A `CommunityPrivacySettings` (Kör 4) csak `visibility`+`audience_default` mezőt hordoz, nincs leaderboard-specifikus oszlop. Az opt-in állapot ehelyett egy ÚJ, e kör tulajdonában lévő `community_leaderboard_opt_ins` táblában él (ADR 0418 D2).

## 3. Scope

**Benne van:** leaderboard projekció KIZÁRÓLAG verified resultból · metric-direction, tie-breaker, cohort, difficulty-band dokumentálva · friends, club, challenge-global scope; NINCS all-time total XP global lista · a felhasználó explicit opt-in nélkül nem jelenik meg public scope-ban · saját rank endpoint + cursor pagination · Flutter leaderboard accessible rank sorral, verified-badge magyarázattal · disqualification/delete után determinisztikus projekció-frissítés.

**NINCS benne (tilos):**

- Bármilyen all-time, összesített XP-alapú globális ranglista.
- A verification-logika módosítása (Kör 22 lezárt szerződése).
- `docs/adr/**` — az ADR 0418-at a Claude írja.
- A Kör 4 `community_privacy_settings`/`profile.py` módosítása (ADR 0418 D2 — önálló tábla helyette).
- Admin/mod "disqualify" endpoint építése (ADR 0418 D5 — teszt-szintű DB-mutáció helyette).

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `backend/app/community/services/leaderboard_service.py` | ÚJ |
| `backend/app/community/models/leaderboard.py` | ÚJ |
| `backend/app/community/routers/leaderboards.py` | ÚJ |
| `backend/alembic/versions/e09_r23_0017_community_leaderboard.py` | ÚJ |
| `lib/features/community/domain/repositories/challenge_repository.dart` | **§0.0 bővítés** — `LeaderboardEntry` osztály hozzáadása, `leaderboard()` szignatúra VÁLTOZATLAN (ADR 0418 D1) |
| `lib/features/community/data/repositories/challenge_repository_impl.dart` | **§0.0 bővítés** — a MÁR deklarált `leaderboard()` teste bekötve (ADR 0418 D1, ugyanaz a hibaosztály, mint E09-R22 `challenges.py`) |
| `lib/features/community/presentation/screens/leaderboard_screen.dart` | ÚJ |
| `backend/tests/community/test_leaderboard_service.py` | ÚJ — a §6 cellái |
| `test/features/community/presentation/leaderboard_screen_test.dart` | ÚJ |

**Tilos zóna:** `backend/app/community/services/challenge_verification_service.py` (csak olvasás) · `backend/app/community/models/profile.py` (Kör 4, ADR 0418 D2) · `lib/features/community/domain/entities/community_challenge.dart` (ADR 0418 Kontextus 6.) · `docs/adr/**` (az `0418-leaderboards-and-opt-in-competition.md` kivételével, amit a Claude ír) · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések (ADR 0418 — D1–D6, teljes szöveg ott)

### 5.1 A leaderboard KIZÁRÓLAG `verified` eredményből épül

A projekció WHERE-feltétele explicit `verification_state = 'verified'` — `pending`/`unverified`/`rejected` sorok soha nem kerülnek a rangsorba.

**NEM elfogadható gyengítés:** egy "jóhiszemű" projekció, ami pending eredményt is beleszámol "amíg a verification lefut" — ez pontosan a nem-ellenőrzött lokális XP globális megjelenését engedné meg.

### 5.2 NINCS all-time total XP globális lista

Minden leaderboard egy KONKRÉT challenge-hez vagy egy dokumentált időszakos ablakhoz kötött — sosem egy örökös, összesített XP-rangsor.

### 5.3 A megjelenés EXPLICIT opt-in

~~A megjelenéshez a Kör 4 privacy-settingsben explicit bekapcsolás szükséges~~ — **ld. §0.0.** A felhasználó alapból (a `community_leaderboard_opt_ins` sor hiánya) NEM jelenik meg public scope-ban; a megjelenéshez az ÚJ, e kör saját táblájában explicit bekapcsolás szükséges (ADR 0418 D2).

### 5.4 Metric-direction, tie-breaker, scope, "own rank" (ADR 0418 D3/D4/D6 — teljes indoklás ott)

- **Metric-direction:** globálisan `higher-is-better` (D3) — az ADR 0417 D6 MÁR élő feltevésének öröklése, nem új döntés.
- **Tie-breaker:** `(metric_value DESC, submitted_at ASC, id ASC)` (D4).
- **Scope:** a leaderboard per-challenge endpoint (`challenge_id` az útvonalban); a "friends/club/challenge-global" nézetet a challenge SAJÁT `type` mezője adja, NEM egy kliens-választható paraméter; `friends` típusnál TOVÁBBI follow-graph szűrés fut (D4).
- **"Saját rank endpoint":** backend-only ebben a körben (router + service), a Flutter-bekötés egy KÉSŐBBI kör dolga — egyik A1–A7 cella sem igényli (D6, Kontextus 6.).

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Csak verified eredmény kerül a leaderboardra | `test_leaderboard_service.py` |
| A2 | Tie-breaker sorrend dokumentált és determinisztikus | `test_leaderboard_service.py` |
| A3 | Opt-out felhasználó nem jelenik meg public scope-ban | `test_leaderboard_service.py` |
| A4 | Friends-scope csak a follow-gráf alapján látható userek eredményét mutatja | `test_leaderboard_service.py` |
| A5 | Pagination stabil, nincs duplikált sor | `test_leaderboard_service.py` |
| A6 | Disqualification/delete után determinisztikus projekció-frissítés — **teszt-szintű DB-mutációval szimulálva, ADR 0418 D5** (nincs admin endpoint ebben a körben) | `test_leaderboard_service.py` |
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

1. `leaderboard.py` — a projekció-modell (`CommunityLeaderboardOptIn` tábla, ADR 0418 D2; és ha materializált projekciót választasz, a leaderboard-entries tábla is) + tie-breaker/cohort/difficulty-band dokumentáció.
2. `leaderboard_service.py` — kizárólag verified forrásból építő query, opt-in ellenőrzés, `higher-is-better` rendezés (D3), `(metric_value DESC, submitted_at ASC, id ASC)` tie-break (D4).
3. `leaderboards.py` router — per-challenge leaderboard GET, saját-rank GET, opt-in PUT, cursor pagination (D6).
4. `challenge_repository.dart` — `LeaderboardEntry` osztály hozzáadása (a `leaderboard()` szignatúra VÁLTOZATLAN marad, D1).
5. `challenge_repository_impl.dart` — a MÁR deklarált `leaderboard()` teste bekötve a 3. lépés endpointja ellen (D1).
6. `leaderboard_screen.dart` — accessible rank-sor, verified-badge, a 4–5. lépés `LeaderboardEntry`-jét fogyasztva.
7. Az A6 (disqualification/delete) teszt-szintű DB-mutációs próbája (D5).
8. A valódi-sértés próba §10-be; a §7 mindkét parancsa KÜLÖN futtatva.

## 9. Kockázatok

- **A pending eredmény beszámítása "UX-gyorsításként".** Ez épp azt az invariánst sértené, amit a Kör 22 megalapozott (A1).
- **Az opt-out megkerülése.** Egy elfelejtett ellenőrzési pont a public scope-ban szivárogtatná a privát adatot (A3).
- **Az all-time XP-lista visszacsúszása.** Csábító "funkció", de a §15.6 SDD kifejezetten kizárja az első verzióból.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
