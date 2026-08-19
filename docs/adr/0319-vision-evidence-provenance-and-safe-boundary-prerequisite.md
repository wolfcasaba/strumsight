# ADR 0319 — Vision evidence provenance és biztonságos boundary előfeltétel

- **Státusz:** elfogadva (E07-R25 pre-flight, 2026-08-19)
- **Kör:** E07-R25 — Analyze és Computer Vision evidence integráció
- **Implementer motor:** MiniMax (`tools/mm-round.sh`), dispatch előtt halt
- **Kapcsolódó:** ADR 0260 (nyers média tilalma), ADR 0261 (bizonytalanság),
  ADR 0262 (capability), ADR 0193 (Vision nested public boundary),
  `docs/LESSONS.md` L190 és L308

## Kontextus

Az E07-R25 célja az Audio Analysis és a Computer Vision származtatott,
confidence-aware jelének bevezetése a Practice Generator prioritásába. A
pre-flight a jelenlegi `main @ 90df4d04`-en két egymástól független szerződési
rést mért:

1. A Practice Generator `EvidenceSource` enumja csak `learn`, `progress`,
   `analyzeV2` és `selfReport` értékeket ismer
   (`lib/features/practice_generator/domain/model/skill_evidence.dart:17-21`).
   Nincs hiteles `vision` provenance, ezért egy Visionből jövő mérés nem
   perzisztálható úgy, hogy a forrása igaz maradjon.
2. A feature-gyökér `vision/public.dart` raw-közeli landmark-, geometry-,
   provider- és presentation-típusokat is exportál. A meglévő szűk
   `vision/domain/integration/public.dart` ilyen típusokat nem enged át, de
   jelenleg nem ad skillhez kötött, numerikus performance-evidence-et sem.

Az Audio Analysis és Vision flagjei a `FeatureFlags` default konstruktorában
és környezeti alapértékében is OFF-ok (`feature_flags.dart:24-43`, `80-99`),
ezért az új contract nem kapcsolhat be rolloutot és nem teheti a Visiont a
tervezés előfeltételévé.

## Döntés

Az E07-R25 jelenlegi briefjét H3-mal megállítjuk; a bridge nem implementálható
helyesen az engedélyezett fájlokban. A follow-up kör előtt a briefnek pontosan
ezt a két, külön tesztelt változást kell engedélyeznie:

1. A Practice Generator evidence-modellben egy explicit Vision provenance
   változatot, annak serializációs/enum regressziós tesztjével. Tilos egy
   Vision-mérést `analyzeV2`-ként jelölni.
2. Egy Vision-owned, nested `public.dart` boundaryt, amely kizárólag
   származtatott, raw-media-mentes, skillhez rendelt numerikus értéket,
   confidence-et, capability/observation állapotot és stabil outcome-azonosítót
   ad át. Landmark, frame, kamera-koordináta, fájlútvonal, provider és UI típus
   ezen a felületen tilos.

Az adapter csak ezt a szűk contractot importálhatja. Vision hiányában vagy
`notObservable`/unavailable állapotában üres vagy explicit unavailable
eredményt kell adnia: az nem válhat alacsony skill-értékeléssé, és nem
okozhat üres tervet.

## Következmények

- Nincs E07-R25 implementer-dispatch, PR vagy merge ezen a pre-flighton.
- A következő brief a megnevezett model- és Vision-contract fájlokat,
  célzott tesztjeiket, és a raw-boundary valódi-sértés próbáját tételesen
  felveszi az `allowed_paths` listába.
- L190 alapján a wide `vision/public.dart` továbbra sem megengedett kerülőút;
  L308 alapján az új tesztnek a tényleges adapter→evidence útvonalon kell
  megőriznie a confidence/provenance mezőket.
