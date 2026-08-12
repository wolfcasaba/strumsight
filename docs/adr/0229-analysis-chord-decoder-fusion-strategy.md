# ADR 0229 — Analysis chord decoder fusion strategy

- **Állapot:** elfogadott (E06-R11 pre-flight, 2026-08-12)
- **Kör:** E06-R11 — Chord evidence, segmentation és decoder provenance
- **Kapcsolódó:** SDD Epic 6 §13.3–13.6; ADR 0220, ADR 0226

## Kontextus

A shipping Analyze chord-idővonal jelenleg a DSP `ClipAnalyzer._chordPass`
kimenete. A Lab ML-dekóder diagnosztikát adhat, de nem cserélheti le a
shipping kimenetet mérési bizonyíték nélkül. A V2 `ChordSegment` már létezik
az audio-analysis domainben; az evidence és provenance ezért ezen a meglévő,
publikus modellen jelenik meg additív módon.

## Döntés

1. A default decoder **DSP primary**, az ML eredmény **advisory/Lab**. A flag
   kikapcsolt útja bitre a meglévő DSP idővonalat adja.
2. Kísérleti fusion csak az új, alapértelmezetten `false`
   `analysisExperimentalFusionEnabled` flag alatt futhat. Egyetértéskor az
   eredmény változatlan; ellentmondáskor a dokumentált súlyozott döntés jelöli
   `fused` forrással és csökkent confidence-szel az eredményt.
3. A meglévő `ChordSegment` kapja meg additív, forráskompatibilis módon a
   segment-azonosító, decoder source és provenance adatait. A constructor új
   paraméterei defaultot kapnak, hogy a korábbi V2 producer és codec érintetlen
   maradjon. A frame-szintű, `derived` evidence köztes adat; top-k címke vagy
   no-chord valószínűség nem szintetizálható a végleges V1 címkéből.
4. A shipping default megváltoztatása kizárólag az E06-R29 evaluation
   számszerű, reprodukálható eredménye alapján dönthető el. Addig sem DSP
   konfiguráció, sem ML-súly/asset, sem `lib/features/analyze/**` nem módosul.

## Következmények

- A V1 UI-adapter változatlanul a nyers címkét vetíti ki; normalizálás nem
  enharmonikus megjelenítési policy.
- A szegmens confidence dokumentált frame-időtartam-súlyozott aggregátum,
  nem konstans érték.
- A frame evidence perzisztenciája nem része ennek a körnek; a tárolási policy
  az E06-R21 tárgya.
