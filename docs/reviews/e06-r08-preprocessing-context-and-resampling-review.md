# E06-R08 — Review

Brief: `docs/rounds/e06-r08-preprocessing-context-and-resampling.md`  
Diff: `git diff 72e6676..8671172`  
Reviewer: Terra-fallback orchestrátor, izolált `/tmp/review-e06-r08` klón  
Dátum: 2026-08-11  
Verdikt: APPROVED (javító kör után)

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 0

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | nulla-másolat, immutable input | ✅ | `preprocessing_stage_test.dart`, valódi-sértés próba F1 alatt |
| 2 | 44.1/48 kHz floor mapping | ✅ | `preprocessed_audio_test.dart` cellamátrix + property seed 42 |
| 3 | v1 downmix mátrix | ✅ | `preprocessing_stage_test.dart:124–156`, mutation-próba |
| 4 | original dynamics megőrzése | ✅ | `preprocessing_stage_test.dart:38–73` |
| 5 | DC-offset parity 4.9/5.0/5.1 ms fixture | ✅ | `63ba278`, canonical PCM-ből származó fixture-mátrix |
| 6 | flag minden környezetben OFF | ✅ | `preprocessing_stage_test.dart:162–173` |
| 7 | ADR 0225 resampling-döntés | ✅ | `docs/adr/0225-analysis-preprocessing-and-resampling-policy.md` |
| 8 | V1 tiltott útvonalak érintetlenek | ✅ | wrapper + kézi scope-audit, 10 engedélyezett implementer-út |

## Scope-audit

Az implementer diffje (`72e6676..8671172`) 10 utat érint; mind a brief
`allowed_paths` listáján szerepel. `python3 tools/scope-audit.py --repo .
--brief docs/rounds/e06-r08-preprocessing-context-and-resampling.md --base
72e66767a68741dde544ba498f901b967fc78b77` → `Legacy scope audit OK`.

## Megállapítások

### F1 — MAJOR — A DC-offset paritás-hármas nem a preprocesszálás viselkedését méri

- **Fájl:** `test/features/audio_analysis/engine/preprocessing_stage_test.dart:101–120`; `lib/features/audio_analysis/engine/preprocessing/preprocessing_config.dart:24–25`
- **Probléma:** a 4.9/5.0/5.1 ms cellák kizárólag
  `PreprocessingConfig.isOnsetParityWithinTolerance` numerikus comparatorát
  hívják. Egyik sem futtat `PreprocessingStage`-et `removeDcOffset: true`
  konfigurációval, nem állít elő szintetikus DC-eltolt inputot, és nem méri a
  canonical PCM-ből származó onset- vagy chord-timeline eltérését.
- **Hatás:** a brief §6 kifejezett paritás-követelménye és falszifikációs
  cellája nem bizonyított; bármely DC-offset implementáció átcsúszhat úgy,
  hogy a threshold helper továbbra is zöld.
- **Kötelező javítás:** adj a három cellához determinisztikus, DC-eltolt
  fixture-t, amely a stage valódi canonical kimenetét adja át az onset/chord
  mérésnek; a származtatott delta 4.9 ms és 5.0 ms esetén zöld, 5.1 ms-nál
  piros legyen. A teszt közvetlenül a preprocesszálásból származó adatot
  ellenőrizze, ne csak a tolerancia-comparatort.
- **Ellenőrzés:** a célzott preprocessing teszt és a brief szerinti teljes
  `tools/round-gate.sh test/features/audio_analysis test/property test/app test/features/analyze`.
- **Státusz:** FIXED (`63ba278`): a 10 kHz-es, determinisztikus DC-offset
  ramp `PreprocessingStage` valódi canonical PCM-jét méri; a rising-edge
  evidence 49/50/51 mintája rendre pontosan 4.9/5.0/5.1 ms. A célzott teszt
  `+7: All tests passed!` eredménnyel újrafutott.

## Valódi-sértés próbák

Az izolált klónban végzett, majd `apply_patch`-csel visszaállított próbák:

1. a `PreprocessingStage` default early-returnját `if (false)`-ra rontva a
   nulla-másolat teszt piros lett (`Expected: true; Actual: false`);
2. a 5 ms comparator `<=` operátorát `<`-re rontva a pontosan 5000 µs cella
   piros lett;
3. a downmix átlagot az első csatornára cserélve az ellenfázisú mátrix piros
   lett (`Actual: [0.8, -0.4]`).

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény | Ellenőrizve |
|---|---|---|
| implementer helyi gate | minden lépés zöld | ✅ a wrapper-log teljes összegzése alapján |
| reviewer célzott mutation tesztek | a három őr piros mutációra | ✅ |
| reviewer teljes gate | izolált klónban indítva | ⚠ a jelen harness a hosszú foreground folyamatot output nélkül leválasztotta, befejezési exit-kód nem gyűjthető; F1 miatt amúgy is javító kör szükséges |
| CI | még nincs exact-SHA dispatch | ❌ javítás után kötelező |

## Merge-döntés

F1 lezárt. Az exact-HEAD CI még kötelező; csak annak zöld eredménye után
merge-elhető.
