# NNLS vs CRNN vs hybrid — összehasonlító harness (E14-R27)

- **ADR:** [0539](../adr/0539-chord-engine-comparison-harness.md)
- **Kód:** `lib/features/live/domain/evaluation/chord_engine_comparison.dart`
- **Futtatható harness:**
  `test/features/live/evaluation/chord_engine_comparison_harness_test.dart`
- **Verdikt:** **NEEDS-MEASUREMENT** — a kör nem választ motort.

## 1. Mit csinál

Ugyanazon a fixtúra-készleten futtatja a **shipped** NNLS-chroma → dictionary
→ Viterbi utat (`ClipAnalyzer`, a Live/Analyze chord-útja) és a **shipped**
chord CRNN-t (`assets/ml/chord_crnn.bin` → `MlChordDecoder`), majd mindkettőt
**ugyanazzal** a merge-elt metrika-szerződéssel pontozza
(`computeRecognitionMetrics`, ADR 0509), és egy táblát renderel.

A vetítés: egy chord-**szakasz** a kezdetén kap egy chord-**eseményt** (ez az
a pillanat, amikor a felhasználó címkeváltást lát), az egymást követő
azonos címkéjű szakaszok előbb összevonódnak — így az az implementáció, amely
minden hopban újra kiadja ugyanazt az akkordot, nem kap büntetést.

## 2. Mit állít a teszt — és mit nem

Állítja: mindkét motor **ugyanazokat a bájtokat** kapta (fixtúránként egyező
`inputSha256`), mindkettő **minden fixtúrára** pontozva lett, a tábla
determinisztikus, és a döntés a konstans `NEEDS-MEASUREMENT`.

**Nem** állítja, hogy melyik jobb. A fixtúrák szintetikusak
(`generateSyntheticChordCorpus`), és a Ch14 §12/2 tiltja a generált audió
ground truthként való használatát; a motorválasztás a §7.1 valós korpuszt
igényli ([chord-corpus-plan.md](chord-corpus-plan.md)). A tábla a teszt
logjába kerül (`print`), hogy a körök közti sodródás látható legyen.

## 3. Mely metrikák szerepelnek — és miért pont azok

`chordWeightedAccuracy`, `chordMacroF1`, `chordNoChordF1`,
`chordMacroF1.weakestSupportedRecall`, `falseVisibleChordEventsPerMinute`.

Kimarad: accepted accuracy, coverage, ECE, Brier. Egy chord-**idővonal** nem
hordoz eseményenkénti konfidenciát, ezért ezek itt elfajult konstansok
lennének, nem mérések — a riport ezt ki is írja
(`omittedMetricsNote`), hogy senki ne olvasson egy `1.0000`-t eredménynek.

## 4. A hybrid ág

A harness `engineId`-nként dolgozik, tehát a hybrid kombinátor (consensus /
confidence-weighted / onset-aligned switch / quality-aware fallback)
harmadik motorként, változtatás nélkül beköthető. A kombinátor MAGA nem ebben
a körben született: a Live-oldali stabilizátor és a chord-profilok PKG-A
tulajdona (E14-R28), és a stratégia kiválasztása szintén mérési kérdés.

## 5. Mi kell a döntéshez

1. A §7.1 korpusz (valós telefon-felvételek, grouped holdout);
2. mindhárom út futtatása ugyanazon a korpuszon ezzel a harnesszel;
3. per-label és per-condition bontás (a `recognition_report_renderer`
   csoport-bontása már megvan);
4. latencia/memória az eszközön (E14-R22).

Amíg ez nincs meg, a Live chord-útja marad az NNLS+Viterbi, a CRNN pedig a
shadow-ágon mérhető (E14-R26, PKG-E).
