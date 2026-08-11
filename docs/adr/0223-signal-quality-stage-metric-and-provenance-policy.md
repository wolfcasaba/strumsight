# ADR 0223 — Signal quality stage metrika- és provenance-policy

- **Státusz:** Elfogadva (E06-R07 pre-flight, 2026-08-11)
- **Kör:** E06-R07 — Signal quality stage
- **Implementer motor:** `sonnet-impl`; az ADR-t az orchestrátor írta a
  pre-flightban (ADR 0055).
- **Epic:** [Chapter 7 — Epic 6: Audio Analysis 2.0](../sdd/07-epic-06-audio-analysis-2.md),
  Kör 7; §11.2–§11.6
- **Kontext-ADR-ek:** [0216](0216-analysis-confidence-calibration-and-abstention.md),
  [0218](0218-analysis-metric-id-and-version-governance.md),
  [0219](0219-analysis-capability-aware-publication.md),
  [0220](0220-audio-analysis-v2-parallel-rollout-boundary.md)

## Kontextus

**Mért 2026-08-11-én, `main` HEAD `10e2d495`:** a R02
`SignalQualityReport` szerződése hét numerikus, véges/tartományellenőrzött
tényt és warning-listát tartalmaz: `overall`, `peakDbfs`, `rmsDbfs`,
`noiseFloorDbfs`, `clippedSampleRatio`, `silentRatio`, `tonalness`,
`measured`, `warnings`. Sem aktív-régió aránynak, sem spektrális flatnessnek,
sem mezőszintű `degraded` jelzőnek nincs publikus helye. Az R04 pipeline a
stage `id`/`version` értékeit már immutable `stageVersions` provenance-ként
gyűjti, de nincs konfigurációs provenance-bag.

Az SDD Kör 7 új, determinisztikus felvételminőségi tényeket kér. Ezek nem
hangforrás-felismerés és nem játékminősítés: a felhasználó teljesítményére
vonatkozó címkéknek nincs mérési alapjuk. A küszöbök valós felvételekre még
nem kalibráltak; az evaluation E06-R29 feladata.

## Döntés

1. A stage kizárólag `PcmAnalysisInput`-ból, lokálisan és determinisztikusan
   számol. A peak/RMS/noise-floor dBFS, clipping- és csendarány a R02 riport
   megfelelő mezőibe kerül; a tonalness a spektrális flatnessből képzett
   proxy. Az aktív-régió arány belső döntési primitív, nem új publikus mező.
2. A csend és egyéb logaritmikus sarokesetek a dokumentált `-120.0 dBFS`
   padlóra clampelődnek. A stage nem publikál `NaN`-t vagy végtelent; a
   részarányok `[0,1]` tartományban maradnak.
3. A rövid klip a számszerű peak/RMS/clipping tényeket továbbra is kiadja;
   a kevésbé megbízható tonalness/noise-floor kontextust stabil,
   `inputQuality`-típusú warning jelöli. A warning felvételi körülményről
   szól, nem a játékos minősítéséről, és nem állít beszédet, dobot vagy más
   hangszert.
4. A `QualityThresholds.version` és a `SignalQualityStage.version` mindig
   azonos. Így a már létező R04 `stageVersions` provenance a küszöb-policy
   verzióját is hordozza; a zárt R02 domainmodell nem bővül.
5. A stage nem hívja az `AnalysisStageContext.publishResult` metódust. Csak
   saját fázis-progresszt jelezhet; terminális pipeline-eseményt kizárólag az
   `AnalysisPipeline` publikálhat.

**Nem elfogadható:** `DspConfig` vagy V1 DSP-paraméter retunolása; hangforrás
vagy játékos minősítése; a report contract bővítése; külső könyvtár vagy
cross-feature belső DSP-import; nem véges riportérték; idő- vagy véletlenfüggő
számítás.

## Következmények

- Az implementáció új, feature-private quality-primitíveken és a R02
  `SignalQualityReport` meglévő contractján marad; V1 Analyze változatlan.
- A képlet-, ablak- és küszöbértékek kanonikus leírása a körrel együtt
  commitolt `docs/rag/chunks/019-signal-quality-metrics.md`; az értékek
  ideiglenesek az E06-R29 valós-audió evaluationig.
- A jövőbeli capability resolver (R19) a teljes reportot és warningokat
  használhatja, de ez a kör nem old fel capabilityt és nem drótoz UI-t.
- Ha később új public minőségmező, konfiguráció-provenance vagy tényleges
  stage-termináljelzés kell, azt új, saját scope-os ADR-rel és domain/pipeline
  változtatással kell megtervezni.

## Elutasított alternatívák

- **A R02 riport kibővítése aktív-régió, flatness és degraded mezőkkel.**
  Elvetve: a kör konkrétan a meglévő contractra épül; a bővítés külön domain
  változtatás, codec- és migrációs következményekkel.
- **A live DSP `DspConfig` vagy meglévő FFT-primitív újrahasznosítása.**
  Elvetve: tiltott cross-feature belső importot vagy shipping-DSP retune-t
  igényelne, mindkettő körön kívüli kockázat.
- **Kész hangforrás-osztályozás.** Elvetve: mérési/model-evidencia nélkül
  túlzó állítás lenne; a flatness/tonalness csak jelstatisztikai proxy.
