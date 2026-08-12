# ADR 0230 — Beat grid és tempo curve bevezetési határa

- **Státusz:** Elfogadva (E06-R12 pre-flight, 2026-08-12)
- **Kör:** E06-R12 — Beat grid és tempo curve
- **Kapcsolódó szerződések:** SDD Ch7 §9.4, §14.1–14.6; [ADR 0221](0221-legacy-analysis-v2-migration-mapping.md), [ADR 0226](0226-clip-analyzer-stage-boundary-and-fallback-provenance.md), [ADR 0229](0229-analysis-chord-decoder-fusion-strategy.md)

## Kontextus

Az előre elkészített R12 brief egy új `TempoPoint` domain típust és target
timebase-et írt elő. A pre-flight a mai `main`-en kimérte, hogy
`domain/analysis_timeline.dart` már exportál egy `TempoPoint` típust, amelyet
az `AnalysisTimeline`, a V1 migrációs adapter és a codec tesztje használ. A
név ismételt exportja ambiguous public API-t okozna. Azt is kimértük, hogy az
`AnalysisTarget` csak a következő, E06-R13 kör saját contractja; R12-ben nem
létezik. Végül az `AnalysisMetricId` katalógus zárt, és nem fogadja el a
tempo-azonosítókat, ezért ezeket nem lehet `AnalysisMetricResult`-ként
publikálni a katalogus módosítása nélkül.

## Döntés

1. R12 új görbe-pontja `TempoCurvePoint`, külön
   `domain/rhythm/tempo_curve_point.dart` fájlban. A meglévő
   `AnalysisTimeline.TempoPoint` nem változik, és R12 nem köti be az új
   görbét a perzisztált dokumentumba.
2. A target-first branch csak az R12-saját `BeatGridTargetInput` értékobjektumot
   fogadja: rendezett beat-időket és `beatsPerBar`-t. Ez adapter-bemenet,
   nem `AnalysisTarget`; az E06-R13 a saját snapshot szerződéséből később
   alakíthatja át.
3. `tempo.legacy_bpm.v1` és `tempo.median_bpm.v1` a R12 `TempoCurve` helyi,
   dokumentált kimeneti címkéi. Nem `AnalysisMetricResult` rekordok, nem
   kerülnek `AnalysisDocument.metrics`-be, és nem bővítik a zárt
   `AnalysisMetricId` katalógust.
4. A legacy BPM érték a V1 `_bpmFromStrums` képletének adaptere marad:
   kevesebb mint két esemény esetén 0, a 0.05 s-nál nem nagyobb intervallumok
   eldobása, felső medián, majd 30–300 BPM clamp. Az R12 saját median-tempója
   ettől külön kimenet.
5. A target-illesztés, dokumentum-/codec-persistálás és UI bekötés későbbi
   körök feladata. R12 csak tiszta, exportálható domain/engine építőkockát
   ad; így a V1 shipping út viselkedése változatlan marad.

## Elutasított alternatívák

- Újabb `TempoPoint` exportálása: a meglévő nyilvános típus mellett ambiguous
  exportot okozna.
- A meglévő `AnalysisTimeline.TempoPoint` bővítése: adapter-, codec- és
  migrációs contract módosulna, miközben ezek a fájlok R12 scope-ján kívüliek.
- R12-beli `AnalysisTarget`: átlépné az E06-R13 saját domain felelősségét.
- Nem katalogizált tempo-metrikák publikálása: az R02 fail-closed metric
  contractját kerülné meg.

## Következmények

- A beat grid és a tempo curve már tesztelhető, offline domain/engine
  eredmény, de nem módosítja a ma használt V1 Analyze eredményt vagy a tárolt
  V2 dokumentumot.
- A későbbi target és persistence köröknek explicit adaptert, illetve
  katalogizált/persistálási döntést kell készíteniük; nem támaszkodhatnak
  hallgatólagos R12-bekötésre.
