# E14-R27 — NNLS vs CRNN vs hybrid: közös pontozó harness

- **Státusz:** LESZÁLLÍTVA (harness) / **PARTIAL** (a döntés NEEDS-MEASUREMENT)
- **ADR:** [`0539`](../adr/0539-chord-engine-comparison-harness.md)
- **Csomag:** PKG-B · **Készült:** 2026-09-09
- **Doksi:** [`docs/eval/chord-engine-comparison.md`](../eval/chord-engine-comparison.md)

## 1. Cél

Legyen egy hely, ahol a **szállított** NNLS+Viterbi út és a **szállított**
chord CRNN ugyanazon a bemeneten, ugyanazzal a merge-elt metrika-szerződéssel
mérhető össze — és ahol a kód **szerkezetileg képtelen** győztest hirdetni.

## 2. Mért kiindulóállapot

- A Live akkordútja végig NNLS-chroma → `ChordDictionary` →
  `ViterbiChordDecoder`; a `chord_crnn.bin` egyetlen betöltője a
  `lib/features/analyze/providers/analyze_providers.dart` (Lab mód).
- Van egyezés-diagnosztika (`MlChordDecoder.agreementFraction`), de nincs
  közös **pontozás** a két út között.
- Valós, címkézett chord-korpusz nincs.

## 3. Scope

BENNE: a pontozó/vetítő tiszta réteg (`chord_engine_comparison.dart`), az
invariáns-ellenőrzések, a determinisztikus tábla, és egy futtatható harness,
amely a VALÓDI `ClipAnalyzer`-t és a VALÓDI `chord_crnn.bin`-t hajtja meg
szintetikus fixtúrákon.

KÍVÜL: a hybrid kombinátor (PKG-A, E14-R28); bármely motor-választás; a Live
bekötés (PKG-E, E14-R26).

## 4. Fájlok

Új:
- `lib/features/live/domain/evaluation/chord_engine_comparison.dart`
- `test/features/live/evaluation/chord_engine_comparison_test.dart`
- `test/features/live/evaluation/chord_engine_comparison_harness_test.dart`
- `docs/eval/chord-engine-comparison.md`

## 5. Kockázatok

- A harness valódi ML-inferenciát futtat (CQT + CRNN) — a fixtúrák
  szándékosan rövidek (2 × 3 s, 44,1 kHz), hogy a CI-suite ideje ne szaladjon
  el.
- A rendszer `print`-tel írja ki a táblát; ez szándékos (sodródás-láthatóság),
  `// ignore: avoid_print`-tel jelölve.

## 6. Acceptance

| # | Kritérium | Állapot |
|---|---|---|
| 1 | Mindkét motor ugyanazon a bemeneten (azonos `inputSha256`) fut | **PINNED-BY-TEST** |
| 2 | Hiányos rács / duplikált futás / hash-eltérés = tipizált hiba | **PINNED-BY-TEST** |
| 3 | Mindkét motor pontozva van minden fixtúrán | **PINNED-BY-TEST** |
| 4 | Az azonos címkéjű szomszédos szakaszok összevonódnak | **PINNED-BY-TEST** |
| 5 | A tábla determinisztikus és megnevezi a kihagyott metrikákat | **PINNED-BY-TEST** |
| 6 | A verdikt konstans `NEEDS-MEASUREMENT`; a kód nem rangsorol | **PINNED-BY-TEST** |
| 7 | Melyik chord-út pontosabb | **NEEDS-MEASUREMENT** (§7.1 korpusz + eszköz-latencia) |

## 7. Verifikáció

Lokálisan nem futtatható. A harness a CI-ben fut le először; a kiírt tábla a
job-logban lesz olvasható.

## 10. Handoff

- **PKG-A:** ha a hybrid kombinátor elkészül, harmadik `engineId`-ként
  köthető be, a harness módosítása nélkül.
- **PKG-E:** a shadow-ág (E14-R26) által gyűjtött valós idővonalak
  ugyanebbe a `ChordEngineRun` alakba illenek.
