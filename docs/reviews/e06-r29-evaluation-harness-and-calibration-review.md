# E06-R29 — Review

Brief: `docs/rounds/e06-r29-evaluation-harness-and-calibration.md`  
Diff: `git diff 6ce59b5e..cd6be314`  
Reviewer: Codex / gpt-5.6-terra  
Dátum: 2026-08-13  
Verdikt: CHANGES REQUIRED

## Összegzés

BLOCKER: 0 · MAJOR: 3 · MINOR: 0 · NOTE: 0

Az izolált review-klónban a teljes helyi round gate zöld, és a gépi
scope-audit a 19 módosított útvonalat mind engedélyezettnek találta. Két
eldobható, valódi-sértés próbateszt mégis pontatlan evaluation-metrikát
bizonyított; a javítás után egy harmadik, azonos matching-hibacsalád maradt a
beat- és pitch-metrikában. Merge tilos.

## Acceptance criteria

| # | Kritérium | Állapot | Bizonyíték |
|---|---|---|---|
| 1 | Typed parser-mátrix | ✅ | `evaluation_manifest_parser_test.dart`, review gate |
| 2 | Determinisztikus, útvonalmentes report | ✅ | `evaluation_report_test.dart`, review gate |
| 3 | Kilenc metrika és szeletek | ❌ | F1 / F2 / F3 torzítja az onset-, chord-segment-, beat- és pitch-metrikát |
| 4 | Ismert-válaszú cellák | ❌ | F1 egy érvényes optimális párosításnál rossz TP/F1 alapot ad |
| 5–6 | Kalibrációs küszöb és ECE | ✅ | `calibration_fitter.dart` célzott tesztjei, review gate |
| 7 | Regressziós kapu | ❌ | F1/F2 javítása után a futtatott baseline és a regression constants felülmérendők |
| 8–12 | Privacy/dataset/ADR/mátrix | ✅ | scope audit, fixture és ADR 0249 review |

## Scope-audit

`python3 tools/scope-audit.py --repo /tmp/review-e06-r29 --brief ... --base
6ce59b5e` → `Legacy scope audit OK` (19 changed path, 0 generated/ignored).
Nincs workflow-, `tool/ci`- vagy bináris-audio módosítás.

## Megállapítások

### F1 — MAJOR — A greedy event-matcher nem maximalizálja a one-to-one találatokat

- **Fájl:** `lib/features/audio_analysis/data/evaluation/evaluation_runner.dart:236-259`
- **Probléma:** a növekvő elvárt idősort feldolgozó, lokálisan legközelebbi
  választás elvehet egy későbbi elvárt eseménytől egy olyan detektálást,
  amellyel globálisan két párosítás lenne lehetséges.
- **Bizonyíték:** az eldobható review-tesztben `expected=[50, 90]`,
  `detected=[0, 55]`, `tolerance=50`. A mai kód 50→55 párost választ, majd
  90-hez nincs jelölt: TP=1. A helyes egy-egy párosítás 50→0 és 90→55:
  TP=2. A próba `Expected: 2; Actual: 1`-gyel piros.
- **Hatás:** onset precision/recall/F1 és timestamp MAE alul- vagy túlbecsült;
  a report nem valós pontosságot mér.
- **Kötelező javítás:** determinisztikus, maximum-cardinality one-to-one
  timestamp matcher (tie-breakerrel), és a fenti counterexample permanens
  tesztje az engedélyezett `evaluation_runner_test.dart` fájlban.
- **Ellenőrzés:** a counterexample TP=2; a meglévő ismert-válaszú cellák és a
  teljes gate zöld.
- **Státusz:** OPEN

### F2 — MAJOR — Egy detektált chord segment többször számolható el

- **Fájl:** `lib/features/audio_analysis/data/evaluation/evaluation_runner.dart:347-369`
- **Probléma:** minden expected segment külön `detected.any(...)` keresést
  végez; nincs claimed/one-to-one állapot. Ugyanaz a detektált szegmens ezért
  több azonos címkéjű expected szegmenst is igazolhat.
- **Bizonyíték:** az eldobható review-tesztben `expected=C[0,100], C[100,200]`,
  `detected=C[0,200]`. A 100%-os overlap miatt mindkét expected segmentet
  matchednek jelöli, `Actual: 1.0`; a csak egyetlen detektált segment miatt a
  helyes segment accuracy `0.5`, így a próba `Expected: 0.5; Actual: 1.0`-val
  piros.
- **Hatás:** a chord segment accuracy eltünteti a határ-elvétését és hamis
  regressziós baseline-t produkál.
- **Kötelező javítás:** egy detektált segment legfeljebb egy expected segmentet
  igazolhasson; egyértelmű, determinisztikus jelöltválasztás és permanens
  counterexample teszt szükséges az `evaluation_runner_test.dart`-ben.
- **Ellenőrzés:** a fenti eset pont `0.5`, a normál egyezések továbbra is
  zöldek; futtasd újra a toolt, majd a baseline- és regression-számokat csak
  a tényleges új stdout alapján frissítsd.
- **Státusz:** OPEN

### F3 — MAJOR — A beat- és pitch-matching még a hibás greedy algoritmust használja

- **Fájl:** `lib/features/audio_analysis/data/evaluation/evaluation_runner.dart:335-361, 455-480`
- **Probléma:** F1 után a `matchEvents` már maximum-cardinality bipartite
  matchinget használ, de `matchTimes` (beat alignment) és
  `_pitchCentsErrors` továbbra is a korábbi, lokálisan legközelebbi greedy
  választást tartja meg. Így azonos érvényes időablakban eldobnak optimálisan
  párosítható eseményt/pitch-pointot.
- **Bizonyíték:** az eldobható review-tesztben `expected=[50,90]`,
  `detected=[0,55]`, `tolerance=50`: a beat matcher `Expected: 2; Actual: 1`.
  Ugyanez pitch-pointokkal (`50ms/220Hz`, `90ms/440Hz`; `0ms/220Hz`,
  `55ms/440Hz`) két párosítás mellett 0 és 1200 cents, tehát 600 átlagot adna;
  a mai kód az első pontot elveszítve `Expected: 600; Actual: 1200.0`-t ad.
- **Hatás:** beat alignment accuracy és pitch cents error nem a valós
  one-to-one maximális illesztést méri; az evaluation report pontatlan.
- **Kötelező javítás:** mindkét út ugyanazt a maximum-cardinality,
  determinisztikus time matcher-t használja; permanens counterexample tesztek
  az engedélyezett `evaluation_runner_test.dart` fájlban.
- **Ellenőrzés:** beat matched count=2 és pitch cents mean=600 a fentivel;
  futtasd újra a toolt és a tényleges output alapján igazíts baseline-t, ha
  szükséges.
- **Státusz:** OPEN

## Gate-bizonyíték

| Gate | Ellenőrzött eredmény |
|---|---|
| `tools/round-gate.sh test/features/audio_analysis test/tooling` | ✅ zöld az izolált `/tmp/review-e06-r29` klónban |
| Scope audit | ✅ 19/19 engedélyezett út |
| Valódi-sértés próba | ❌ F1 és F2 pontos, reprodukált piros kimenettel |

## Merge-döntés

ADR 0052 szerint a két nyitott MAJOR miatt merge tilos. Javító kör és
újra-review szükséges.
