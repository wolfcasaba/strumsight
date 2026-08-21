# E08-R18 — Független Sol review

- **Brief:** `docs/rounds/e08-r18-weekly-quest-and-consistency.md`
- **Diff:** `2a73ec31..ef717615`
- **Reviewer:** Codex `gpt-5.6-sol`
- **Dátum:** 2026-08-21
- **Verdikt:** APPROVED

## Összegzés

BLOCKER: 0 · MAJOR: 0 nyitott (2 javítva) · MINOR: 0 · NOTE: 2.

## Acceptance criteria

| Pont | Státusz | Bizonyíték |
|---|---|---|
| A1 | teljesült | 3/4/5/6/7 active-days + -1/8 rejection zöld; a `5 → 7` valódi mutáció piros |
| A2 | teljesült | 360 perc → 6, 180 perc → 3 |
| A3/A8 | teljesült | same-ID `max(previous, observed)` és cross-ID replacement isolation zöld; az unconditional-max mutáció `Expected 0, Actual 4` hibával piros |
| A4–A7 | teljesült | derivation, pinned FNV, four-kind cross-wiring és típusos rollover cellák zöldek |
| A9 | teljesült | improvement fail-closed és replacement progress-isolation együtt zöld |
| A10 | teljesült | immutable candidate-lista és pure-source őr |

## Scope és gate

- Első wrapper scope-audit: `ok`, base `2a73ec31`, 4 módosított engedélyezett út.
- Javító wrapper + kézi scope-audit: `ok`, base `8714277b`, 3 módosított
  engedélyezett út, 0 generated/ignored.
- Az orchestrátor saját pre-flight/review ADR-pontosítása külön dokumentációs
  commit; a két implementer-szegmens auditja ezért a hiteles scope-bizonyíték.
- Re-review izolált klón: `/tmp/review-e08-r18-sol-ef717615`.
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
- **Státusz:** FIXED (`ef717615`). A shipping cross-ID cella zöld; a reviewer
  unconditional-max mutációja `Expected 0, Actual 4` hibával piros.

### F2 — MAJOR — A kötelező 3/7 availability végpont és a 0..7 inputhatár nincs őrizve

- **Fájl:** `lib/features/gamification/application/weekly_quest_generator.dart:36`,
  `test/features/gamification/application/weekly_quest_generator_test.dart:12`, `:76`
- **Probléma:** a Chapter 9 3-day/7-day kötelező cellái nem active-days targetet
  mérnek; `availableDays: 8` elfogadott input.
- **Hatás:** a heti explainability invalid, hétnél nagyobb rendelkezésre állást
  is visszaadhat, a specifikált végpontokra nincs közvetlen regresszióőr.
- **Kötelező javítás:** exact 3→3 és 7→5 active-days cella, továbbá -1 és 8
  constructor rejection; a 4/5/6 inkluzív cap-hármas maradjon.
- **Státusz:** FIXED (`ef717615`). A 3/4/5/6/7 és -1/8 mátrix zöld.

### N1 — NOTE — A cap-őr valódi mutációt fog

`_maximumRequiredActiveDays = 7` mellett az A1 cella `Expected 5, Actual 6`
hibával piros lett; restore után a teljes kör-gate zöld.

### N2 — NOTE — Friss klón első l10n analyze futása átmenetileg stale outputot látott

Mindkét friss review-klón első gate-je 38 pre-existing achievement-l10n getter
hiányával állt meg, noha a `prepare-flutter-generated.sh` lefutott. Ugyanazon
változatlan HEAD-en a második gate rendre zöld lett (1771 helyett 1773
formázásba vont Dart fájl). Product fájl nem változott; a jelenséget a záró
LESSONS-be mérési snagként rögzítjük.

## Re-review gate — `ef717615`

- `tools/round-gate.sh test/features/gamification/application/weekly_quest_generator_test.dart`
  → format zöld; analyze zöld; 14/14 célzott teszt zöld; architecture zöld;
  secret scan 3185 fájl / 0 finding; l10n 1532 message parity zöld.
- Cap `5 → 7` mutáció → A1 piros (`Expected 5`, `Actual 6`).
- Cross-ID branch unconditional max mutáció → A3/A8 piros (`Expected 0`,
  `Actual 4`). Mindkét mutáció restore után tiszta diffet hagyott.

## Merge-döntés

Correctness review APPROVED. Nyitott BLOCKER/MAJOR nincs. Merge csak az új
review-commit utáni exact-SHA Full Gate + Router CI és freshness ellenőrzés
után engedélyezett.
