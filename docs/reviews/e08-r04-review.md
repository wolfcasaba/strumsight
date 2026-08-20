# E08-R04 — Review

Brief: `docs/rounds/e08-r04-activity-outbox-and-reliable-processing.md`
Diff: `3f9481b6..0e6c4472`
Reviewer: Codex (independent orchestrator review) · Dátum: 2026-08-20
Verdikt: APPROVED

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 1

Az első review F1 leletét a `1a429d72` javította; az azt követő security
review S2/S3 leleteit a független Terra javító kör `0e6c4472`-je zárta.
Az ismételt, pontosan erre a commitra rögzített `/tmp` klónban a teljes
kötelező gate zöld, és a scope-audit két megváltozott, engedélyezett útvonalat
talált.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | Reward-hiba nem teszi sikertelenné a sessiont | ✅ | `activity_ingestor_test.dart`: A1 cella zöld |
| A2 | Sikertelen drain utáni ismétlés feldolgozza az eseményt | ✅ | A2 crash/retry cella zöld |
| A3 | Kétszeri drain egy ledger-bejegyzést ad | ✅ | A3 idempotencia cella zöld |
| A4 | Ack csak sikeres ledger-írás után | ✅ | A4 cella; korábbi valódi-sértés próba piros, visszaállítva |
| A5 | Sérült rekord nem blokkolja a mögötte lévőt | ✅ | A5 cella zöld |
| A6 | Karantén lekérdezhető és restart után megmarad | ✅ | A6/F1 restart- és corrupt-payload cellák zöldek |
| A7 | Korlát fölött a legrégebbi rekord karanténba kerül | ✅ | A7 alatta/rajta/fölötte mátrix és restart-cella zöld |
| A8 | Retry-limit karanténba visz | ✅ | A8 cella zöld |

## Scope-audit

`tools/scope-audit.py --repo /tmp/review-e08-r04-fixed-jLToFR --brief
docs/rounds/e08-r04-activity-outbox-and-reliable-processing.md --base
f698af1d…` → `Legacy scope audit OK` (2 changed path, 0 generated/ignored).
Mindkét út a brief listáján szerepel.

## Javított megállapítások

### F1 — MAJOR — A perzisztált karantén restart után nem kérdezhető le

- **Státusz:** FIXED (`1a429d72`). `_ensureLoaded()` hibatűrően visszatölti a
  karantént; a friss repository-instance regressziós cella zöld.

### S2 — MAJOR — Pendingből karanténba átmozgatás crash-ablaka

- **Státusz:** FIXED (`0e6c4472`). A pending, attempts és quarantine ugyanabba
  az `JsonDocumentStore` snapshotba kerülnek; a régi külön quarantine-kulcs
  csak olvasható migrációs fallback maradt.
- **Valódi-sértés próba:** az új snapshot `quarantine` mezőjének ideiglenes
  elhagyása után a restart-A6 és a capacity-restart A7 teszt piros lett;
  visszaállítás után mind 15 célteszt zöld.

### S3 — MAJOR — Release-ben hiányzó pozitivitás-ellenőrzés

- **Státusz:** FIXED (`0e6c4472`). `_requirePositive` runtime
  `ArgumentError.value`-t dob mindkét konstruktorparaméterre.
- **Valódi-sértés próba:** az őr kiiktatására a Validation cella piros lett,
  mert `capacity: 0` mellett a konstruktor visszatért; visszaállítva zöld.

### F2 — NOTE — A `dropped` név retryra váró rekordot jelöl

Nem blokkoló, meglévő public report-elnevezés; átnevezése scope-n kívüli API
felületet érintene, ezért nem része ennek a javításnak.

## Gate-bizonyíték ellenőrzése

Az izolált, `0e6c4472`-re rögzített klónban futott:

```bash
ROUND_GATE_SLEEP_SECONDS=0 ROUND_GATE_RESULT_FILE=/tmp/e08-r04-review-gate.json \
  tools/round-gate.sh test/features/gamification/application/activity_ingestor_test.dart
```

Mind a hat lépés zöld: format, analyze, 15 célteszt, architecture, secrets,
l10n. A teljes suite, property gate és APK továbbra is a merge-előtti CI kapu.

## Merge-döntés

Nincs nyitott BLOCKER vagy MAJOR. A merge a választott workflow exact-SHA
success, a Router CI és az aktuális `main`-szinkron után engedélyezett.
