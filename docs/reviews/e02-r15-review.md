# Review — E02-R15 Chord Change mód

- **Kör:** E02-R15 — Chord Change mód
- **Branch:** `codex/e02-r15-chord-change-mode`
- **Implementer motor:** MiniMax M3 (egy stall → resume, `0740d55` + `7be8c49`)
- **Reviewer:** Claude (Opus 4.8), READ-ONLY, izolált `/tmp` klón
- **ADR:** 0081 (pre-flightban írva)
- **Dátum:** 2026-08-01
- **Verdikt (1. kör):** CHANGES REQUESTED — 1 MAJOR + 1 MINOR (1 NOTE)
- **Verdikt (javító kör #1 után, `a2933d6`):** **APPROVED** — MAJOR-1 és MINOR-1
  lezárva; friss `/tmp` klón gate zöld, CI run
  [30681908643](https://github.com/wolfcasaba/strumsight/actions/runs/30681908643)
  **success** (teljes suite + property + APK).

## 0. Javító kör #1 — lezárás (`a2933d6`)

- **MAJOR-1 zárva:** `chord_change_analyzer_test.dart` új „meter boundaries"
  group — 3/4 (`Meter(beatsPerBar: 3)`) és külön 4/4 cella, bar-boundary
  váltással → `correct` + mért késés. A §10 handoff A7-sora javítva. A teszt a
  hiányt PIROSRA fogta volna (ütem-specifikus assert).
- **MINOR-1 zárva:** 179999 µs→`unstable` és 180001 µs→`correct` él-cellák
  (`stableDuration` explicit assert-tel) — a `>=` mindkét oldala mérve.
- Scope tiszta (csak a teszt-fájl + §10 handoff módosult). A reviewer
  eldobható próbái (`zzz_probe_*`) csak `/tmp` klónban léteztek, törölve.

## 1. Gate-újrafuttatás (saját kézzel, `/tmp/review-e02r15`)

Friss klón + `flutter pub get` (a fresh klón `.dart_tool`-ja hiányzott → az első
futás analyze-PIROS-a package-resolution artefaktum volt, nem kód-hiba), majd:

```
tools/round-gate.sh test/features/practice/ test/property/chord_change_property_test.dart test/core/l10n_parity_test.dart
→ format ZÖLD · analyze ZÖLD · test/features/practice ZÖLD ·
  test/property ZÖLD · l10n_parity ZÖLD · architecture ZÖLD
```

A gate zöld — de a zöld gate NEM bizonyíték (E02-R04/R05 tanulság). A reviewer
eldobható próbatesztekkel mért (lásd §4).

## 2. Scope-audit

`git diff --stat main...HEAD` — mind a 13 fájl a brief §4 engedélyezett listáján
(a `docs/adr/0081` + brief-§0.0/§10 az én pre-flightom / az implementer §10-e).
`lib/features/learn/` **0 sor**. `application/**` / `data/**` / meglévő service-ek
**érintetlenek**. Screen-módosítás **+9 sor** (csak a `_ModeView` becsatolás).
**Scope tiszta.**

## 3. Súlyossági tábla

| # | Súly | Fájl:sor | Lelet |
|---|---|---|---|
| MAJOR-1 | MAJOR | `test/features/practice/domain/chord_change_analyzer_test.dart` | **A7 (3/4 ütem) nincs mérő teszttel lefedve**, és a §10 handoff hamisan tulajdonítja egy nem-kapcsolódó, meglévő fájlnak |
| MINOR-1 | MINOR | `test/features/practice/domain/chord_change_analyzer_test.dart` | **A2 három-cellás küszöbteszt hiányos** — csak a 180000 µs→`correct` cella van meg (az A1-correct teszten át); a 179999→`unstable` és 180001→`correct` élcellák hiányoznak |
| NOTE-1 | NOTE | `lib/features/practice/presentation/screens/practice_session_screen.dart:299-300` | futásidejű `analysis: null` — a mérés nem látszik élőben (scope-helyes, R18) |

## 4. Acceptance criteria tételesen + próbatesztek

- **A1** (öt kimenet-ág) — ZÖLD, mind az öt ág külön tesztben (`+73..+77`). OK.
- **A2** (stabilitási küszöb `>=`) — **MINOR-1.** A brief három explicit cellát
  kér (179999/180000/180001 µs); a repóban csak a 180000→`correct` van (A1). A
  **reviewer-próba** (`zzz_probe_boundary_test.dart`, eldobva) mind a hármat
  MÉRTE a szállított analyzeren: `179999→unstable`, `180000→correct (>=)`,
  `180001→correct` — **mind zöld**, tehát a `>=` szemantika HELYES; a hiány
  tiszta teszt-lefedettségi rés, nem korrektségi hiba (a `<`/`<=` mutáns amúgy is
  elbukna a 180000→correct-on). Olcsó pótolni → körben javítandó.
- **A3** (előjeles késés, hiányzó ≠ nulla) — ZÖLD. A teszt `[-50ms, 0, +250ms,
  isNull]`-t vár; a `recognizedChangeDelay` `Duration?`, hiányzáskor **null**
  (nem `Duration.zero`). OK — a brief legfontosabb A3-cellája teljesül.
- **A4** (medián, ≥3 minta) — ZÖLD. 2→`InsufficientData`, 3→200ms, 4→250ms
  (páros: két középső átlaga). OK.
- **A5** (irányított párok + stabil rendezés) — ZÖLD, **jó teszt**. A tie-break
  teszt 8-akkordos szekvenciával **valódi holtversenyt** állít (C→D és D→C
  medián = 100ms), forward vs. reversed bemenettel ugyanazt a győztest (`C→D`,
  kanonikus sorrend) várja. A `slowestPair` `_comparePairs`-szel bont, **nem**
  `Map`-iterációval (`chord_pair_stats.dart:288-299`). A brief Map-order-csapdája
  lefedve. OK.
- **A6** (nem állít mérésen túlit) — ZÖLD. Szöveg-audit mindkét ARB-ben:
  `grep -rin "clean\|tiszta\|minden húr\|gyors vált"` → egyetlen találat a
  **pre-existing** `tunerInTune: "Tiszta"` (nem chord-change). A chord-change
  szövegek: „Recognized and stable chord", „Different chord recognized", „No
  chord detected", „Chord label was not stable", „Not enough signal…". Az
  `insufficientSignal`/`noDetection` külön ikon+szín, nem piros hiba. OK.
- **A7** (3/4 ütemhatár + külön 4/4 cella) — **MAJOR-1.** A kör három ÚJ
  teszt-fájljában `grep "beatsPerBar: 3\|waltz\|3/4"` → **0 találat**. A §10
  handoff azt állítja, az A7-et a `practice_session_review_probes_test.dart`
  „A7 cellái" fedik — de az egy **pre-existing** fájl
  (`test/features/practice/application/`, a kör-diffben NINCS benne), és **nem
  hivatkozik** a `ChordChangeAnalyzer`-re → nem bizonyíthatja az új kód 3/4-es
  viselkedését. A **reviewer-próba** (`zzz_probe_meter34_test.dart`, eldobva)
  MÉRTE: 3/4-es (`beatsPerBar: 3`) egy-akkord-per-ütem váltás →
  `correct`, késés `100ms` — az analyzer **valóban meter-agnosztikus** (csak az
  `ExpectedChordSegment` határokat olvassa). Tehát a kód HELYES, de a **kötelező
  acceptance-cella (A7) mérő teszt nélkül maradt**, ráadásul hamis
  coverage-állítással a handoffban. Ez pontosan az a „zöld gate mögötti
  tesztelt-nélküli előírt viselkedés", amit a review-nak el kell kapnia →
  **MAJOR**, javító körben pótlandó (3/4 + explicit 4/4 cella).
- **A8** (a11y/i18n/layout) — ZÖLD. a11y label-ek, 320×568 és 915×412 overflow-
  mentes, `l10n_parity` zöld. OK.
- **A9** (property gate) — ZÖLD, öt invariáns `PROPERTY_SEED=42`. OK.
- **A10** (domain-tisztaság + scope) — ZÖLD (`architecture` zöld, `learn/` 0). OK.

## 5. NOTE-1 — futásidejű null-wiring (nem blokkol)

A `_ModeView` `chordChanges` ága `analysis: null, latestChange: null`-t ad a
`ChordChangeView`-nak, így az élő appban a mérés nem jelenik meg. Ez **scope-
helyes**: az analízis forrása (verdict+observation → analyzer) az
`application/**` rétegben élne, ami R15-ben **tilos zóna**; a brief §3 az élő
session-megjelenítést opcionálissá teszi („a session-nézet **már mutathat**
belőle"). R18 köti be. Nincs teendő ebben a körben.

## 6. Javítási irány (a javító kör motorja: MiniMax M3, ugyanaz)

- **MAJOR-1:** `chord_change_analyzer_test.dart` — új A7 cella: 3/4-es
  (`beatsPerBar: 3`) akkordváltás-gyakorlat, egy-akkord-per-ütem
  `ExpectedChordSegment`-ekkel → a statisztika ugyanúgy áll elő
  (`correct` + mért késés); és egy explicit 4/4 párcella. A §10 handoff A7-sorát
  javítsd a valós tesztre hivatkozva (a hamis `review_probes` hivatkozást vedd
  ki).
- **MINOR-1:** ugyanabban a fájlban a 179999 µs→`unstable` és 180001 µs→`correct`
  élcellák (a `>=` teljes bizonyítása). Olcsó, a diffet nem hizlalja.
- A reviewer-próbák (`zzz_probe_*`) eldobhatók, csak a `/tmp` klónban léteztek,
  a kör-fába nem kerültek.

**A verdikt frissül** a javító commit sha-jával, ha a gate újra zöld és a MAJOR
zárul (a lezáró teszt PIROSRA fogta volna a hiányt).
