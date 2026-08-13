# ADR 0229 — Chord decoder fusion és evidence-provenance stratégia

- **Státusz:** Elfogadva (E06-R11, 2026-08-12)
- **Kör:** E06-R11 — Chord evidence, segmentation és decoder provenance
- **Kapcsolódó szerződések:** SDD Ch7 §13.3–13.6, [ADR 0220](0220-audio-analysis-v2-parallel-rollout-boundary.md), [ADR 0226](0226-clip-analyzer-stage-boundary-and-fallback-provenance.md)

## Kontextus

A V1 `ClipAnalyzer` csak kész `TimelineChord` spaneket ad az V2 adapternek.
Nincs belőle frame-szintű top-k vagy no-chord valószínűség, és a shipping
timeline ma DSP-eredetű. A Lab ML decoder eredménye külön diagnosztika; annak
shipping felhasználása eddig nem volt reprodukálható szerződéshez kötve.

## Döntés

1. A shipping default **DSP primary, ML advisory**. A nyilvános V1 timeline
   változatlanul a DSP listája; az ML csak Lab-diagnosztika.
2. `analysisExperimentalFusionEnabled` minden környezetben `false`. A flag-off
   `ChordSegmentAssembler.fuse` az eredeti DSP listaobjektumot adja vissza,
   így sem címke, sem határ, sem confidence nem változhat.
3. Flag-on csak azonos számú, indexenként összehasonlítható DSP/ML szegmens
   fuzionálható. Egyetértő címke esetén a DSP szegmens marad. Eltéréskor a
   nagyobb confidence-ű címke marad, a source `fused`, a confidence pedig a
   két confidence szorzata. Ez determinisztikusan kisebb a győztesnél, ezért
   az ellentmondás nem jelenik meg túlzott bizonyosságként.
4. A V1 spanekből készülő `ChordFrameEvidence` `derived`: top-k listája üres,
   top-confidence-e és no-chord valószínűsége null. Kész címkéből tilos
   valószínűséget kitalálni. A teljes evidence megszerzése a Lab ML út és a
   későbbi R18/R29 mért feladata.
5. A `ChordSegment` additív mezői a determinisztikus ID, `source`,
   `modelManifestId` és `confidenceSource = heuristic`. A segment confidence
   a hozzá tartozó, confidence-szel rendelkező frame-ek frame-időtartammal
   súlyozott átlaga; evidence nélkül 0.0, nem kitalált 1.0.
6. Az assembler alap policyja V1-paritásos: nulla minimum-hossz, tranzciens
   merge kikapcsolva, no-chord nem zárja le a nyitott spant, a záró segment a
   clip végéig tart. A `closeOnNoChord`, minimum-hossz és tranzciens-ablak
   csak explicit policyval módosítható.
7. A belső címke-normalizálás sharps alapú kanonikus alakot használ
   (`Db → C#`, `Cmaj/CM → C`, `Cmin → Cm`). Ez nem UI megjelenítési döntés.
8. A `DecoderSource` domain value: a domain nem importál engine-t; az
   engine-oldali út csak ezt a domain enumot exportálja. A top-k frame evidence
   nem kerül automatikusan a perzisztált dokumentumba. A storage-szerződés R21
   feladata; a jelen körben a codec változatlan.

## Elutasított alternatívák

- ML primary vagy automatikus fusion: a mért R29 evaluation előtt megváltoztatná
  a shipping decoder viselkedését.
- Kész V1 címkéből származtatott top-k/no-chord score: hamis mérési bizonyíték.
- No-chord alapértelmezett szegmenszárása vagy minimumhossz: megtörné a V1 UI
  által használt span-paritást.
- Enharmonikus UI-spelling az engine-ben: a kulcs- és nyelvfüggő megjelenítési
  policyt helytelenül a domain/engine rétegbe vinné.

## Visszavonási feltétel

A shipping default kizárólag E06-R29 számszerű evaluation eredménye alapján
változhat. Az ADR frissítésének előfeltétele a DSP-only és a jelölt fusion
stratégia azonos fixture-ökön végzett, reprodukálható összevetése, beleértve a
disagreement/abstention arányt és a confidence-kalibrációt. Addig a flag
alapértelmezetten kikapcsolt marad.

## Következmények

**E06-R30 (2026-08-13):** E06-R29 csak szintetikus evaluation harness-t szállított, nullával lezárt valódi evaluation sorral; a visszavonási feltétel nem teljesült, ezért a fusion flag helyesen OFF marad.

- A V1 UI és DSP lánc érintetlen marad.
- A V2-ben frame- és segment-provenance explicit, de a V1-ből származó
  evidence teljességi korlátja is explicit.
- A későbbi storage körnek meg kell határoznia, mely aggregált provenance mezők
  perzisztálódnak anélkül, hogy több ezer frame top-k adatát mentené.
