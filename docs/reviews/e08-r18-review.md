# E08-R18 — Független Sol review

- **Brief:** `docs/rounds/e08-r18-weekly-quest-and-consistency.md`
- **Diff:** `2a73ec31..6300f497`
- **Reviewer:** Codex `gpt-5.6-sol`
- **Dátum:** 2026-08-21
- **Verdikt:** CHANGES REQUIRED

## Összegzés

BLOCKER: 0 · MAJOR: 2 · MINOR: 0 · NOTE: 1.

## Acceptance criteria

| Pont | Státusz | Bizonyíték |
|---|---|---|
| A1 | részleges | 4/5/6 cap zöld és a `5 → 7` valódi mutáció piros; a Chapter 9 explicit 3/7 active-days cellái hiányoznak |
| A2 | teljesült | 360 perc → 6, 180 perc → 3 |
| A3/A8 | **nem teljesült** | eldobható cross-ID próbateszt: filtered improvement `4` unitja active-days replacementre került |
| A4–A7 | teljesült | derivation, pinned FNV, four-kind cross-wiring és típusos rollover cellák zöldek |
| A9 | részleges | improvement fail-closed, de replacement progress-isolation hiányzik |
| A10 | teljesült | immutable candidate-lista és pure-source őr |

## Scope és gate

- Wrapper scope-audit: `ok`, base `2a73ec31`, 4 módosított engedélyezett út.
- Kézi scope-audit: `Legacy scope audit OK`, 4 path, 0 generated/ignored.
- Izolált klón: `/tmp/review-e08-r18-sol-6300f497`.
- A generált l10n első analyzer-futása átmenetileg 38 pre-existing gettert nem
  látott; ugyanazon előkészített klón változatlan HEAD-jén az ismételt teljes
  kör-gate `format/analyze/11 test/architecture/secrets/l10n` minden lépése
  zöld. Ezt nem számítom product findingnak.

## Megállapítások

### F1 — MAJOR — Progressz átvihető eltérő quest objective-re

- **Fájl:** `lib/features/gamification/application/weekly_quest_generator.dart:24`, `:192`, `:203`
- **Probléma:** a previous progress scalar, nincs stable quest ID-hoz kötve.
  Eligibility-változáskor új candidate választódhat, majd megkapja a régi
  objective unitjait.
- **Bizonyíték:** improvement-only korábbi `4` unit + measurement unavailable +
  active-days fallback → `Expected: 0`, `Actual: 4`.
- **Hatás:** más objective mérés nélküli completiont és későbbi téves rewardot
  kaphat.
- **Kötelező javítás:** a brief §0.0.1 szerint previous progresshez stable
  `previousQuestId`; same-ID esetben monotonic max, cross-ID replacementnél
  csak observed progress. Reprodukáló teszt maradjon a shipping suite-ban.
- **Státusz:** OPEN.

### F2 — MAJOR — A kötelező 3/7 availability végpont és a 0..7 inputhatár nincs őrizve

- **Fájl:** `lib/features/gamification/application/weekly_quest_generator.dart:36`,
  `test/features/gamification/application/weekly_quest_generator_test.dart:12`, `:76`
- **Probléma:** a Chapter 9 3-day/7-day kötelező cellái nem active-days targetet
  mérnek; `availableDays: 8` elfogadott input.
- **Hatás:** a heti explainability invalid, hétnél nagyobb rendelkezésre állást
  is visszaadhat, a specifikált végpontokra nincs közvetlen regresszióőr.
- **Kötelező javítás:** exact 3→3 és 7→5 active-days cella, továbbá -1 és 8
  constructor rejection; a 4/5/6 inkluzív cap-hármas maradjon.
- **Státusz:** OPEN.

### N1 — NOTE — A cap-őr valódi mutációt fog

`_maximumRequiredActiveDays = 7` mellett az A1 cella `Expected 5, Actual 6`
hibával piros lett; restore után a teljes kör-gate zöld.

## Merge-döntés

Két nyitott MAJOR miatt merge tilos. Ugyanaz a Terra motor kap egy javítókört;
utána friss izolált klónban teljes re-review és új exact-SHA CI szükséges.
