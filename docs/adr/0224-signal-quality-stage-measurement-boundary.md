# ADR 0224 — Signal-quality stage mérési és publikációs határa

- **Státusz:** Elfogadva (E06-R07 pre-flight, 2026-08-11)
- **Kör:** E06-R07 — Signal quality stage
- **Implementer motor:** Terra (`gpt-5.6-terra`); az ADR-t a Terra-fallback
  orchestrátor írta a pre-flightban.
- **Kapcsolódó szerződések:** [ADR 0215](0215-analysis-document-versioning.md),
  [ADR 0217](0217-analysis-raw-audio-retention.md),
  [ADR 0219](0219-analysis-capability-aware-publication.md), valamint az
  E06-R04 stage contract.

## Kontextus

Az E06-R02 `SignalQualityReport` már létező, fail-closed domain szerződés:
hét véges numerikus értéket és warning-listát tárol. Az E06-R07 viszont a
teljes PCM-klipen új jelminőségi méréseket vezet be. A kör briefje aktív-régió
arányt, rövid-klip degraded állapotot és threshold-verziót is előír; ezeknek
nincs mezője a merge-elt domain-reportban. Az R04 `AnalysisStage<I, O>`
szerződése megenged eltérő bemenetet és kimenetet, de a jelenlegi
`AnalysisPipeline<T>` csak azonos állapottípusú stage-eket komponál.

## Döntés

1. Az R07 `SignalQualityStage` önálló
   `AnalysisStage<ValidatedPcmAnalysisInput, SignalQualityStageResult>`.
   A stage tiszta, determinisztikus számításokat fut a validált, lokális PCM-en;
   nyers audio nem kerül logba, hálózatra vagy perzisztens tárolóba.
2. `SignalQualityStageResult` az engedélyezett
   `engine/quality/signal_quality_stage.dart` fájlban marad. Tartalmazza a
   meglévő `SignalQualityReport`-ot, az aktív-régió arányt, a rövid-klip miatt
   degraded metrikák jelölőit és a `QualityThresholds` verzióját. A
   `public.dart` ezt a stage-contractot additívan exportálja.
3. A már merge-elt `SignalQualityReport`, `AnalysisProvenance`,
   `AnalysisPipeline` és a V1 `DspConfig` **nem változik**. A threshold-verzió
   a stage-outputban és a stage `version` provenance-be kerülésén keresztül
   auditálható; a későbbi work-state/pipeline-összekötés külön kör feladata.
4. A stage csak felvételi feltételekre utaló, stabil `AnalysisWarning`
   kulcsokat ad. Hangforrást és játékminőséget nem osztályoz vagy állít.

## Következmények

- Az R07 teljesíti a részmetrikák hozzáférhetőségét domain-redesign nélkül.
- A stage a rövid klipből továbbra is peak/RMS/clipping értéket szolgáltat;
  csak a nem elég megfigyelhető zaj-/tonalness-metrikákat jelöli degradednek.
- A `docs/rag/chunks/019-signal-quality-metrics.md` a képletek, küszöbök és
  ideiglenes kalibráció elsődleges, verziózott forrása. Valós-felvételes
  kalibráció továbbra is E06-R29 döntési kapu.

## Elutasított alternatívák

- **Az R02 domain-report bővítése:** scope-on kívüli, és a pipeline/codec
  fogyasztóinak szerződését indokolatlanul előre módosítaná.
- **A heterogén stage közvetlen betolása a `AnalysisPipeline<T>`-be:** a mai
  T→T kompozíciós szerződés megsértése lenne.
- **A részmetrikák eldobása az `overall` javára:** ellentmond a Ch7 és a brief
  „a grade nem rejti el a részmetrikákat” követelményének.
