# ADR 0539 — NNLS vs CRNN vs hybrid: közös pontozó harness, döntés NÉLKÜL

**Státusz:** elfogadva (2026-09-09) · **Kör:** E14-R27 · **Kapcsolódik:** ADR 0509 (metrika-szerződés), Ch14 §4.5, §12/1 („thresholdok vak átírása tilos”)

## Kontextus (mért)

- A Live akkordútja végig **NNLS-chroma → `ChordDictionary` →
  `ViterbiChordDecoder`**; a szállított `chord_crnn.bin` egyetlen betöltője a
  `lib/features/analyze/providers/analyze_providers.dart` (Lab mód), a Live
  izolátum csak a strum-súlyokat kapja meg.
- Létezik egy diagnosztika (`MlChordDecoder.agreementFraction`), amely a két
  idővonal **egyezését** méri — de nincs olyan pont a fán, ahol a két motor
  **ugyanazzal a pontozó szerződéssel** (E14-R08 metrikák) mérhető össze.
- Ground truth-tal ellátott valós chord-korpusz nincs (ADR 0538).

## Döntés

### D1 — Egy pontozó, két (vagy több) motor, ugyanaz a bemenet

`domain/evaluation/chord_engine_comparison.dart`: motoronként egy
`ChordEngineRun`, fixtúránként egy `ChordComparisonFixture` (ground truth +
`inputSha256`), és a pontozás a merge-elt `computeRecognitionMetrics`-szel
történik. Nincs második metrika-implementáció.

### D2 — Csak invariánsokat állítunk, győztest SOSEM

A harness hibát dob, ha a rács hiányos (`incompleteCoverage`), ha két motor
más bájtokat kapott (`inputHashMismatch`), vagy ha ugyanaz a motor kétszer
szerepel egy fixtúrán (`duplicateRun`). A riport `decision` mezője a
**konstans** `NEEDS-MEASUREMENT`; a típusban nincs `winner`, és a teszt
egyetlen cellája sem hasonlítja össze a két motor számait.

### D3 — Szakaszból esemény a szakasz KEZDETÉN, azonos címkék összevonva

A merge-elt metrika esemény-alapú (`chordToleranceMs = 250`). Egy chord-span
a kezdetén ad eseményt (ez az a pillanat, amikor a felhasználó címkeváltást
lát); az egymást követő azonos címkéjű szakaszok előbb összevonódnak, hogy a
hoponként újra kiadó implementáció ne kapjon büntetést a belső
reprezentációjáért.

### D4 — A konfidencia-alakú metrikák KIMARADNAK, megnevezve

Egy chord-idővonal nem hordoz eseményenkénti konfidenciát, ezért az accepted
accuracy, coverage, ECE és Brier itt elfajult konstans lenne. A riport nem
rendereli őket, és `omittedMetricsNote`-ban **kiírja, miért** — egy `1.0000`
elfajult coverage veszélyesebb, mint a hiánya. A detektált események
`confidence: 0` értéke ezért nem állítás a motor bizonytalanságáról.

### D5 — A hybrid harmadik motorként, változtatás nélkül köthető be

A harness `engineId`-nként dolgozik. A kombinátor (consensus /
confidence-weighted / onset-aligned switch / quality-aware fallback) a Live
stabilizátor-oldalán születik (PKG-A, E14-R28); ez a kör nem hoz létre
harmadik dekódert, mert a stratégia kiválasztása maga is mérési kérdés.

### D6 — A futtatható harness szintetikus fixtúrán fut, és ezt kimondja

`test/features/live/evaluation/chord_engine_comparison_harness_test.dart` a
VALÓDI `ClipAnalyzer`-t és a VALÓDI `chord_crnn.bin`-t futtatja — de
`generateSyntheticChordCorpus` fixtúrákon (ADR 0538 D6). A tábla a teszt
logjába kerül, hogy a sodródás látható legyen; egyetlen szám sem lesz tőle
bizonyíték.

## Ami MÉRVE van és ami NINCS

**Mérve:** hogy mindkét szállított motor lefut ugyanazon a bemeneten és
pontozható ugyanazzal a szerződéssel; a harness invariánsai; a riport
determinizmusa.

**NINCS mérve, és ebben a körben nem is dönthető el:** melyik chord-út
pontosabb. Ehhez a §7.1 valós korpusz kell (`docs/eval/chord-corpus-plan.md`),
per-label és per-condition bontással, plusz az eszközön mért latencia/memória
(E14-R22). Addig a Live chord-útja marad az NNLS+Viterbi, a CRNN pedig a
shadow-ágon mérhető (E14-R26).
