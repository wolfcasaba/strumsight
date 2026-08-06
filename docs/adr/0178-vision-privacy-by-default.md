# ADR 0178 — Vision privacy by default

- **Státusz:** Elfogadva (E05-R01 pre-flight, 2026-08-06)
- **Kör:** E05-R01 — Vision baseline, alapozó ADR-ek
- **Implementer motor:** DeepSeek v4 Pro (`deepseek/deepseek-v4-pro`, Kilo-profil,
  örökölt kézi override, `codex-round.sh`) — az ADR-eket az orchestrátor (Claude)
  írta a pre-flightban (ADR 0055, pipeline-prompt §2).
- **Epic:** [Chapter 6 — Epic 5: Computer Vision](../sdd/06-epic-05-computer-vision.md) §5.1
- **Kontext-ADR-ek:** [0166→0183](0183-vision-no-raw-frame-persistence.md),
  [0132](0132-ai-tutor-privacy-and-consent.md) (privacy-precedens),
  [0056](0056-exclusive-microphone-session.md) (lifecycle-precedens)

## Kontextus

Az Epic 5 kamerát vezet be a StrumSightba. A kameraadat a repó eddigi
legérzékenyebb inputja: a felhasználó arca, környezete és keze kerülhet a
frame-be. Az SDD Ch6 §5.1 alapelve a *privacy by default*: a frame-ek
alapértelmezetten csak memóriában élnek, feldolgozás után a Vision Engine
azonnal elengedi a buffer-referenciát, és raw fotó/videó nem kerül
persistence-be. A meglévő on-device offline-garancia (E01-R16,
`test/app/offline_network_guard_test.dart`) 0-request utat őriz kijelentkezve/
offline — ezt a vision sem törheti meg.

## Döntés

1. **A kamerakép feldolgozása kizárólag a készüléken történik.** Raw frame nem
   kerül hálózatra és nem íródik ki tartós tárba consumer (production) kódban.
2. **A frame-buffer élettartama a feldolgozás.** A Vision Engine az inference
   után azonnal elengedi a frame-referenciát; a pipeline nem tart fenn korlátlan
   frame-historyt (a latest-frame szabály az [ADR 0182](0182-vision-audio-priority-degradation.md)
   degradációs láncában részletezve).
3. **Kamera csak aktív, jelzett előtérben.** App-pause vagy route-leave esetén a
   kamera azonnal leáll; háttérben kamera nem indulhat; a preview külön
   UI-jelzést kap.
4. **Egyetlen kivétel: explicit consentelt Lab capture.** Raw frame kizárólag a
   `visionLabCaptureEnabled` flag mögött (**default OFF**), explicit felhasználói
   művelettel, Lab-build kontextusban rögzíthető — a diagnosztikai út, nem a
   termékút.

**NEM elfogadható** gyengítés: „debug buildben feltölthető a preview",
„opt-in esetén elmenthető az utolsó frame a coaching javításához", vagy bármely
olyan út, amely a raw frame-et consumer kódban tárba írja vagy hálózatra küldi a
`visionLabCaptureEnabled` flag és explicit consent nélkül.

## Következmények

- A vision persistence rétege csak származtatott aggregátumot tárolhat
  (részletek: [ADR 0183](0183-vision-no-raw-frame-persistence.md)).
- A Lab capture consent-flow, redakció és tárolási határidő külön kör (E05
  Lab-blokk) felelőssége; ez a kör csak a boundaryt rögzíti.
- Ebben a körben production kód nem változik (SDD Ch6 Kör 1); a flag az E05-R03
  kerül be default OFF-fal.
- Ez a döntés nem lazítható azért, hogy egy teszt vagy egy demó zöld legyen.

## Elutasított alternatívák

- **Opt-in preview-mentés a termékben.** Elvetve: a raw frame a legérzékenyebb
  adat, és egy „csak ha bekapcsolod" út a termékben normalizálja a tárolást; a
  Lab-flag + explicit művelet külön, ritka, diagnosztikai kontextusba szorítja.
- **Debug-only feltöltés hálózatra.** Elvetve: a debug/consumer határ build-time
  könnyen elmosódik; az offline-garancia (E01-R16) sérülne.
- **Egyetlen `visionEnabled` boolean privacy-kapunak.** Elvetve: a capability- és
  consent-tagolás ([ADR 0179](0179-vision-capability-aware-feedback.md)) finomabb
  őrzést kíván, mint egy globális kapcsoló.
