# ADR 0241 — Analysis overview: presentation input and confidence boundary

- **Státusz:** Elfogadva (E06-R23 pre-flight, 2026-08-12)
- **Kör:** E06-R23 — Overview screen és metric cardok
- **Implementer motor:** sonnet-impl
- **Epic:** [Chapter 7 — Epic 6: Audio Analysis 2.0](../sdd/07-epic-06-audio-analysis-2.md), Kör 23; §25.4–25.5, §25.8
- **Kapcsolódó ADR-ek:** [0219](0219-analysis-capability-aware-publication.md), [0220](0220-audio-analysis-v2-parallel-rollout-boundary.md), [0237](0237-analysis-confidence-combiner-and-capability-resolver.md), [0238](0238-analysis-insight-evidence-and-ranking-boundary.md), [0240](0240-analysis-runner-and-pipeline-boundary.md)

## Kontextus

**Mért 2026-08-12-én, `main` @ `0869fd36`.** A V2 dokumentum a
`CapabilityStatus` négy értékét (`available`, `degraded`, `unavailable`,
`notApplicable`) és a `CapabilityUnavailableReason` okát publikálja.
`CapabilityResolver._statusFor` a domain/engine egyetlen 0.4/0.7 küszöbös
döntési pontja. A `AnalysisMetricResult` ugyanígy a közzétett státuszt,
confidence-et és unavailable-okát hordozza. A presentation a `engine/` zónát
nem importálhatja és nem rekonstruálhat státuszt nyers confidence-ből.

Az R20 rule-értékelése belső, paraméteres `RecommendedAnalysisAction`-t
használ, de a perzisztált `AnalysisDocument` csak az
`AnalysisInsight.recommendedAction` `AnalysisRecommendedAction` enumot őrzi
meg. A route-katalógus és a tényleges router a `lib/app/routing/` alatt él;
a korábbi brief másik, nem létező útvonalat nevezett meg.

## Döntés

1. Az overview constructora `AnalysisDocument`-et kap; a flag-mögötti route
   csak akkor építi fel, ha a `GoRouterState.extra` ilyen dokumentum. Hiányzó
   vagy hibás extra a meglévő fail-closed router útvonalra terelődik, nem
   keres tárolót és nem indít elemzést.
2. `OverviewViewModel` kizárólag meglévő dokumentumértékeket választ,
   rendezett insight-listát korlátoz és lokalizálható megjelenítési adatot
   formáz. Nem importál `engine/`-t, nem aggregál score-t és nem dönt
   capability-státuszt.
3. Az „alacsony confidence” felhasználói állapot a domain által közzétett
   `unavailable` + `CapabilityUnavailableReason.confidenceTooLow` kombináció.
   A badge ezt szöveggel is láthatóvá teszi; a presentationben nincs
   0.4/0.7 küszöb vagy nyers confidence-et státuszra váltó összehasonlítás.
4. Az R20 leíróinak paraméterei nem érhetők el a dokumentumból. Az enumhoz
   tartozó, még be nem kötött UI-akció ezért letiltott és magyarázott;
   paraméteres gyakorlat-, összehasonlítás- vagy Tutor-navigáció nem készül.
5. Az új `/analysis/overview` route csak `audioAnalysisV2Enabled` mellett
   kerül a route-listába. A V1 Analyze képernyő és a domain/engine réteg
   változatlan marad.

## Következmények

**E06-R30 (2026-08-13):** a döntés változatlan; valós eszközös overview ellenőrzés EVAL-34 PENDING.

- A UI nem állíthat gyenge vagy nem elérhető mérésről biztos eredményt.
- A route közvetlen widget- és router-teszttel nyitható flag-on állapotban,
  de a V1-be ebben a körben nem kerül belépőpont.
- A teljes, paraméteres R20 action-leíró perzisztálása külön domain/codec
  döntést igényel; nem ennek a presentation körnek a része.
