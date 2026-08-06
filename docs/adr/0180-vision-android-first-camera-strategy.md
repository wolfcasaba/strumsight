# ADR 0180 — Vision Android-first camera strategy

- **Státusz:** Elfogadva (E05-R01 pre-flight, 2026-08-06)
- **Kör:** E05-R01 — Vision baseline, alapozó ADR-ek
- **Implementer motor:** DeepSeek v4 Pro (`deepseek/deepseek-v4-pro`, Kilo-profil,
  örökölt kézi override, `codex-round.sh`) — az ADR-eket az orchestrátor (Claude)
  írta a pre-flightban (ADR 0055, pipeline-prompt §2).
- **Epic:** [Chapter 6 — Epic 5: Computer Vision](../sdd/06-epic-05-computer-vision.md) §5.7, §11
- **Kontext-ADR-ek:** [0179](0179-vision-capability-aware-feedback.md),
  [0181](0181-vision-manual-calibration-fallback.md)

## Kontextus

A StrumSight ma Android-célú (a `build-apk.yml` release-APK-t Android-ra épít; az
iOS-út nincs CI-ben). Az Epic 5 valós eszközös bizonyítéka (FPS, thermal, soak)
Android-eszközökön gyűlik. Az SDD Ch6 §5.7 model-provider-függetlenséget és
§8.1 rétegszabályt ír elő: a domain nem függhet konkrét platform-API-tól. A
kamera-capture platform-specifikus, a vision domain viszont nem lehet az.

## Döntés

1. **Az Epic Android-on szállít.** A production camera-adapter és a valós
   eszközös mérés Android-célú; a device-mátrix (E05-R01 sablon) Android sorokkal
   indul.
2. **Az iOS a contract szintjén készül el, futó adapter nélkül.** A
   platformfüggetlen capture-contract (SDD §11.1) és a permission-gateway
   szerződése iOS-re is érvényes, de futó iOS-adaptert ez az Epic nem szállít.
3. **A domain platform-független.** A `CameraFrameMetadata`, a landmark- és
   geometria-modellek pure Dart típusok; a konkrét inference-/capture-provider
   interfész mögött él (SDD §5.7).

**NEM elfogadható:** platform-specifikus típus (Android/iOS plugin-osztály,
natív handle, MediaPipe/TFLite/ML Kit API-típus) beszivárgása a vision
domainbe — a domain kizárólag provider-interfészen át éri el a platformot.

## Következmények

- Az iOS-permission-szöveg (`NSCameraUsageDescription`) és az iOS-adapter külön,
  Epic-utáni munka; a baseline rögzíti, hogy ma egyik sincs a repóban.
- A `check_architecture` allowlist NEM bővül a camera-stratégia miatt; a
  platform-adapter a provider-interfész mögé kerül.
- A valós eszközös FPS/thermal/soak számok Android-eszközökön, a device-mátrix
  PENDING sorain gyűlnek (SDD §32, §35).

## Elutasított alternatívák

- **Egyszerre Android+iOS futó adapter.** Elvetve: megkétszerezi a valós eszközös
  bizonyíték-terhet, miközben a CI ma csak Androidot épít.
- **Platformtípus a domainben a gyorsaságért.** Elvetve: sérti az §5.7
  model-provider-függetlenséget és a §8.1 rétegszabályt; a jövőbeli iOS/provider-
  csere lehetetlenné válna.
- **iOS teljes kihagyása a contractból is.** Elvetve: a platformfüggetlen
  capture-contract előre rögzítése olcsó, és megőrzi a későbbi iOS-utat.
