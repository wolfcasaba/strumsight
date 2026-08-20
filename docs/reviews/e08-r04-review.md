# E08-R04 — Review

Brief: `docs/rounds/e08-r04-activity-outbox-and-reliable-processing.md`  
Diff: `3f9481b6..cb0f967b`  
Reviewer: Codex (independent orchestrator review) · Dátum: 2026-08-20  
Verdikt: CHANGES REQUIRED

## Összegzés

BLOCKER: 0 · MAJOR: 1 · MINOR: 0 · NOTE: 1

Az implementer scope-auditja és az ismételt kézi audit is tiszta: 6 módosított
implementációs útvonal mind szerepel a brief engedélyezett listáján. Az
izolált, tényleges `cb0f967b` implementer-HEAD klónban a célteszt 12/12 zöld,
és az A4 valódi-sértés próba valóban pirosra vált. A karantén azonban csak
memóriából olvasható vissza egy app/repository újraindítás után, noha a kód
külön kulcsra már perzisztálja; ez megakadályozza, hogy a diagnostics később
lekérdezze a történeti karantént.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | Reward-hiba nem dob a session mentés fölé | ✅ | célteszt: 1. cella zöld |
| A2 | Sikertelen drain után retry | ✅ | célteszt: 2. cella zöld |
| A3 | Drain idempotens | ✅ | célteszt: 3. cella zöld |
| A4 | Ack csak sikeres ledger-írás után | ✅ | valódi-sértés próba piros: `pending=[]`, visszaállítás után célteszt zöld |
| A5 | Hibás rekord nem blokkol mögötteset | ✅ | célteszt: 5. cella zöld |
| A6 | Karantén lekérdezhető diagnostics számára | ❌ | F1: új repository-példány üres karantént ad |
| A7 | Korlátos sor, oldest quarantine | ✅ | célteszt: 7. cella zöld |
| A8 | Retry limitnél karantén | ✅ | célteszt: 8. cella zöld |

## Scope-audit

Kézi futtatás eredménye: `Legacy scope audit OK` — 6 változott útvonal, 0
generated/ignored és 0 listán kívüli útvonal.

## Megállapítások

### F1 — MAJOR — A perzisztált karantén újraindítás után nem kérdezhető le

- **Fájl:** `lib/features/gamification/data/local_activity_outbox_repository.dart:367-389, 440-462`
- **Probléma:** `_persistQuarantine()` írja az `activityOutboxQuarantineKey`
  JSON-át, de `_ensureLoaded()` csak a pending/attempts documentet olvassa.
  `quarantineRecords()` egy friss repository-példányon ezért üres, még akkor
  is, ha az előző példány already quarantine-ba tett retry-limitet elérő
  rekordot.
- **Hatás:** app restart után a diagnosztika nem látja a felhasználó elveszett
  vagy hibás eseményeit; az A6 ígért lekérdezhető karantén nem tartós.
- **Mért bizonyíték:** eldobható izolált teszt létrehozott egy `maxAttempts: 1`
  retry-limit karantént, majd ugyanazzal a `KeyValueStore`-ral új
  `LocalActivityOutboxRepository`-t épített. A várt `hasLength(1)` helyett az
  actual `[]` volt.
- **Kötelező javítás:** a karantén JSON szerződését explicit, hibatűrő
  dekódolással töltsd vissza `_ensureLoaded()` alatt, a sérült karantén payloadot
  pedig a meglévő tárolási quarantine-minta szerint őrizd meg. Adj committed
  regressziós tesztet a repository-rekonstrukcióra.
- **Ellenőrzés:** `activity_ingestor_test.dart` új restart-cellája; utána a
  brief kötelező `tools/round-gate.sh` artefaktum.
- **Státusz:** OPEN

### F2 — NOTE — A `dropped` jelentésnév a retry-t takarja

- **Fájl:** `lib/features/gamification/data/activity_outbox_repository.dart:155-158`
- **Probléma:** a lista ténylegesen pendingben maradó, később újrapróbálandó
  rekordokat tartalmaz; a "dropped" név elvesztésre utal.
- **Státusz:** OPEN — csak akkor javítsd, ha az F1 minimális diffjébe természetesen beleillik.

## Gate-bizonyíték ellenőrzése

| Gate | Ellenőrzés |
|---|---|
| format | izolált `round-gate` futás: zöld |
| analyze | izolált `round-gate` futás: `No issues found` |
| célzott teszt | izolált `flutter test …activity_ingestor_test.dart`: 12 passed |
| architecture/secrets/l10n | teljes, review-oldali gate-összegzés még újrafuttatandó F1 javítása után |

## Merge-döntés

Nyitott MAJOR miatt merge tilos. Egy MiniMax javító kör indul F1 lelettel;
azután friss izolált review és a teljes kötelező gate következik.
