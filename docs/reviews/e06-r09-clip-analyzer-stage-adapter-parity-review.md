# E06-R09 — Review

Brief: `docs/rounds/e06-r09-clip-analyzer-stage-adapter-parity.md`
ADR: `docs/adr/0226-clip-analyzer-stage-boundary-and-fallback-provenance.md`
Diff: `git diff 71b158b3..5f762ccd` (main → `codex/e06-r09-clip-analyzer-stage-adapter-parity`)
Reviewer: Claude (orchestrátor) · Dátum: 2026-08-12
Verdikt: **APPROVED**

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 2

Független, izolált `/tmp/review-e06-r09` klónban futtatott mérce mind a
kilenc lépésen ZÖLD; a brief §6.1 mérce-mátrixának három sorát valódi
mutációs próbával (nem csak olvasással) igazoltam — mindhárom a várt cellát
vitte pirosra, majd visszaálltam az implementer eredeti kódjára.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | Paritás-mátrix — 9 fixture | ✅ | `clip_analyzer_parity_test.dart` — mind a 9 (silence, two chords, four chords C·G·Am·F, ring-out overlap, single strum, known BPM strum sequence, throwing refiner fallback, empty input, sample rate zero) zöld saját izolált futáson |
| 2 | Számszerű paritás-tolerancia | ✅ | `_expectParity`: chord count egyezés + \|Δstart\|/\|Δend\| ≤ 1 µs, strum count+irány egyezés + \|Δtime\| ≤ 1 µs, `\|Δbpm\| ≤ 1e-9` — mind assertálva minden fixture-ön |
| 3 | Időátváltás küszöb-hármas (0.5/1.5/2.5 µs → 1/2/3 µs, `round()`) | ✅ | `clip_analyzer_stage_test.dart:56-69` pontosan ezt a 3 cellát fixálja; **saját mutációs próba**: `.round()`→`.floor()` → a teszt a várt középső cellán (0.5µs→0µs, elvárt 1µs) PIROSRA vált, visszaállítva |
| 4 | Fallback-provenance (none/heuristic+reason/crnn, ADR 0226 kettős-hívásos technika) | ✅ | `clip_analyzer_stage_test.dart:71-113`, mindhárom cella valós `runClipAnalysis`-hívással (garbage bytes a heuristic cellához, a valódi `assets/ml/strum_crnn.bin` a crnn cellához); **saját mutációs próba**: `_refinerOutcome` mindig `.crnn()`-t adjon → a `fallback` cella PIROSRA vált (`Expected: heuristic, Actual: crnn`), visszaállítva |
| 5 | Provenance-teljesség (5 mező, effektív érték) | ✅ | `clip_analyzer_stage_test.dart:30-34` mind az öt mezőt (`chunkSize=2048`, `chromaMedianWindow=1`, `bassWeight=0.35`, `nnlsWindow=16384`, `nnlsHop=4096`) assertálja; **saját mutációs próba (a brief §6.1 utolsó sora által kifejezetten előírt)**: `clipAnalyzerChunkSize` értékét 999-re rontva a teszt PIROSRA vált, visszaállítva. A `bassWeight` mező típusa `double` (nem nullable) — a `null`-ról effektív értékre oldás szerkezetileg kizárja a „nyers null" hibát |
| 6 | Randomizált paritás property ≥ 50 | ✅ | `analysis_legacy_parity_property_test.dart` — 60 iteráció, `PROPERTY_SEED` env-ből (alapértelmezés 42); **saját ellenőrzés**: `PROPERTY_SEED=987654`-gyel is lefuttatva, ténylegesen más seedet használ (`print`-ben visszaigazolva) és zöld marad |
| 7 | Architektúra — allowlist nem nőtt (≤12) | ✅ | `tool/check_architecture.dart` **byte-azonos** a `main`-nel (`git diff 71b158b3..HEAD -- tool/check_architecture.dart` üres); az allowlist pontosan 12 bejegyzés (közvetlenül megszámolva); `architecture_allowlist_guard_test.dart` zöld; az új `lib/` fájlok kizárólag `analyze/public.dart`-ot és `audio_analysis/**`-t importálnak — nincs közvetlen `clip_analyzer.dart` vagy `live/**` import |
| 8 | V1 érintetlen | ✅ | `git diff --stat` nem tartalmaz `lib/features/analyze/**` vagy `lib/features/live/**` útvonalat; `test/features/analyze` mind a 64 teszt zöld, változatlan formában |

## Scope-audit

Engedélyezett fájlokon kívüli változás: **nincs.** `git diff --stat 71b158b3..5f762ccd` pontosan 9 fájl, mindegyik a brief (pre-flight-revideált) `allowed_paths`-án:

```
docs/rounds/e06-r09-clip-analyzer-stage-adapter-parity.md            (§10 handoff)
lib/features/audio_analysis/engine/analysis_provenance_builder.dart  (ÚJ)
lib/features/audio_analysis/engine/legacy/clip_analyzer_stage.dart   (ÚJ)
lib/features/audio_analysis/engine/legacy/legacy_evidence.dart       (ÚJ)
lib/features/audio_analysis/public.dart                              (export +3 sor)
test/features/audio_analysis/engine/clip_analyzer_parity_test.dart   (ÚJ)
test/features/audio_analysis/engine/clip_analyzer_stage_test.dart    (ÚJ)
test/property/analysis_legacy_parity_property_test.dart              (ÚJ)
test/tooling/architecture_allowlist_guard_test.dart                  (ÚJ)
```

A gépi scope-audit (`.codex-round-status`) egyezik: `scope_audit=ok`,
`scope_audit_changed=9`. `tool/check_architecture.dart` az engedélyezett
listán szerepelt (szűkítésre), de az implementer helyesen NEM nyúlt hozzá —
a meglévő 12 bejegyzés elég volt.

## Megállapítások

### N1 — NOTE — Az öt provenance-konstans a DSP-igazságot tükrözi, drift-őr nélkül

- **Fájl:** `lib/features/audio_analysis/engine/analysis_provenance_builder.dart:59-63`
- **Megfigyelés:** `clipAnalyzerChunkSize`/`clipAnalyzerChromaMedianWindow`/
  `clipAnalyzerBassWeight`/`legacyNnlsWindow`/`legacyNnlsHop` névvel ellátott,
  hardcode-olt konstansok, amik MA pontosan egyeznek a valódi
  `DspConfig.chordBassWeight`/`nnlsWindow`/`nnlsHop` és a `ClipAnalyzer`
  konstruktor-defaultjaival (ellenőrizve: `bassWeight=0.35`,
  `nnlsWindow=16384`, `nnlsHop=4096` — mind egyezik). Ez a duplikáció
  ARCHITEKTURÁLISAN KÉNYSZERÍTETT (a `DspConfig` a tilos `live/**` alatt van,
  a `public.dart` nem exportálja) — nem implementer-hiba.
- **Hatás:** ha egy KÉSŐBBI kör retune-olja a `DspConfig` valamelyik értékét
  (a projekt történetében ez már kétszer megtörtént: round 71, round 182),
  ennek az adapternek a provenance-e csendben ELAVULT értéket jelentene, és
  jelenleg semmilyen teszt nem venné észre — a meglévő tesztek csak a
  hardcode-olt konstanshoz mérnek, nem a `DspConfig`-hoz.
- **Javasolt irány (nem kötelező ebben a körben):** egy test-oldali (a
  `check_architecture.dart` hatályán kívüli, tehát szabadon importálható)
  drift-őr, ami `AnalysisProvenanceBuilder.legacyNnlsWindow`-t közvetlenül
  a `DspConfig.nnlsWindow`-hoz hasonlítja stb. — ha valaha eltérnek, a teszt
  jelezze, hogy az adaptert frissíteni kell.
- **Státusz:** OPEN (nem blokkoló, follow-up-ként hagyva).

### N2 — NOTE — `LegacyClipAnalyzerInput.fromPreprocessedAudio` hívó és teszt nélkül

- **Fájl:** `lib/features/audio_analysis/engine/legacy/legacy_evidence.dart:27-34`
- **Megfigyelés:** a factory a jövőbeli, `PreprocessedAudio`-alapú
  pipeline-hívók számára készült előre, de ebben a körben SEM hívó, SEM
  teszt nincs rá (`grep -rn "fromPreprocessedAudio" test/ lib/` csak a saját
  definícióját találja). Harmatlan holt kód — nem befolyásol semmilyen
  jelenlegi viselkedést, `flutter analyze` sem jelzi.
- **Javasolt irány:** amikor egy jövőbeli kör ténylegesen bedrótozza ezt a
  stage-et egy pipeline-hívóba, adjon hozzá egy egysoros tesztet erre a
  factory-ra is; addig elhagyható lenne, de a jelenléte nem hiba.
- **Státusz:** OPEN (nem blokkoló, follow-up-ként hagyva).

## Mutációs próbák (eldobhatók, mind visszaállítva)

Mindhárom próba a `/tmp/review-e06-r09` izolált klónban futott, a
megosztott munkafa érintése nélkül; mindegyik után `git checkout --` az
érintett fájlra.

| # | Mutáció | Célzott teszt | Eredmény |
|---|---|---|---|
| 1 | `durationFromSeconds`: `.round()` → `.floor()` | `clip_analyzer_stage_test.dart` — „uses round half away from zero…” | PIROS, pontosan a 0.5µs→1µs cellán (`Expected: 1µs, Actual: 0µs`) |
| 2 | `_refinerOutcome`: mindig `_RefinerOutcome.crnn()` | `clip_analyzer_stage_test.dart` — „distinguishes no refiner, inferred fallback, and active CRNN” | PIROS, a `fallback` cellán (`Expected: heuristic, Actual: crnn`); a 9-fixture paritás-teszt VÁLTOZATLANUL zöld maradt (helyesen — a paritás a `strums`/`chords`/`bpm` értékeket nézi, nem a forrás-címkét) |
| 3 | (brief §6.1 utolsó sora által előírt) `clipAnalyzerChunkSize`: `2048` → `999` | `clip_analyzer_stage_test.dart` — „records the effective legacy parameters…” | PIROS (`Expected: 2048, Actual: 999`) |

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény (implementer) | Ellenőrizve (saját, izolált klón) |
|---|---|---|
| format | zöld | ✅ `dart format --set-exit-if-changed`: 1288 fájl, 0 változott |
| analyze | zöld | ✅ `flutter analyze lib/ test/ tool/`: „No issues found!” |
| test/features/audio_analysis | zöld | ✅ 104 teszt zöld |
| test/property | zöld | ✅ 75 teszt zöld (a saját külön `PROPERTY_SEED=987654` futás is zöld) |
| test/tooling | zöld | ✅ 57 teszt zöld (az új guard-teszttel együtt) |
| test/features/analyze | zöld (átírás nélkül) | ✅ 64 teszt zöld, a fájlok a diffben nem szerepelnek |
| architecture | zöld, 12 allowlisted deviation | ✅ byte-azonos `tool/check_architecture.dart`, 12 bejegyzés |
| secrets | zöld, 2214 fájl, 0 lelet | ✅ (a gate-összegzőben megerősítve) |
| l10n | zöld | ✅ |
| CI (teljes suite + property + APK) | — | Ez a jelentés ELŐTT még nem dispatch-elve; a merge előtti lépés (§ „CI dispatch”) |

## Biztonsági review

`risk = "high"` (brief front-matter) → dedikált `security-reviewer` review
**PASS**, 0 CRITICAL/BLOCKER/MAJOR/MINOR, 5 NOTE (mind az unwired állapot
miatt nem-blokkoló, a jövőbeli E06-R22 bekötő körre irányuló hardening —
köztük a szinkron hívás izolátum-konténment hiánya adversariális súlyra és a
dupla-DSP-futás cancellation-granularitása). Lásd
[`docs/reviews/e06-r09-clip-analyzer-stage-adapter-parity-security.md`](e06-r09-clip-analyzer-stage-adapter-parity-security.md).

## CI-bizonyíték

- **Full Gate** (`full-gate.yml`, a `tools/round-ci-plan.py` választása —
  `native_gate=false`, tisztán Dart-diff): **success**, exact-SHA `5f762ccd`.
  https://github.com/wolfcasaba/strumsight/actions/runs/31551186142
- **Router CI**: a diff érinti a `docs/rounds/**`-t, tehát trigger-útvonal —
  **success**, push-eseményen, ugyanazon az exact-SHA-n (`5f762ccd`).
- A dispatch előtti `origin/main` (`71b158b3`) a dispatch és e jelentés
  lezárása között nem mozdult (H8 tiszta) — újra-ellenőrizve merge előtt.

## Merge-döntés

ADR 0052 szerint: minden gate zöld (saját izolált mérés + CI mindkét
workflow-n, exact-SHA) ÉS nincs nyitott BLOCKER/MAJOR (sem az általános,
sem a dedikált biztonsági review-ban) → **merge mehet.** A két NOTE (általános
review) és az öt NOTE (biztonsági review) egyike sem blokkol; mind a
jövőbeli E06-R22 (bekötő kör) brief-jébe viendő follow-up.
