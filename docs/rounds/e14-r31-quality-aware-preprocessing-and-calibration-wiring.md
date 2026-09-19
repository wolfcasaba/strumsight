# E14-R31 — Minőség-tudatos előfeldolgozás, eszköz-adaptációs seam, kalibrációs bekötés (ADR 0552)

- **Kör:** E14-R31 · **Csomag:** PKG-A (2. hullám) · **ADR:** 0552
- **Ág:** `claude/laptop-apk-debug-prompt-kys4oa`
- **Környezet:** nincs Dart/Flutter SDK → **lokális gate nem futtatható**;
  egyetlen mérce a CI (`full-gate.yml`, `build-apk.yml`).

## 1. Cél

Három szállítmány, **egyetlen meglévő DSP-küszöb hangolása nélkül**:

1. minőség-tudatos bemeneti előfeldolgozás **MECHANIZMUSA**: a
   `SignalQualitySnapshot`-ot fogyasztó fokozat, korlátozott szint-
   normalizálással `tooQuiet`/`tooLoud` állapotban, `clipping`-en soha —
   zászlóval teljesen kikapcsolható, kikapcsolva **bit-azonos**;
2. `DeviceAudioProfile` mint **fogyasztói seam**, identitás alapértékkel (az
   audio-setup varázsló, E14-R14, lesz a termelő);
3. a PKG-B kalibrációs rezolverének élő bekötése: a
   `StrumPrediction`/`ChordPrediction` `calibratedConfidence` mezője
   mostantól **rezolver-verdikt**, nem hardkódolt `null`, és a selective
   prediction döntése read-only módon kivezetve.

## 2. Mért állapot (a kör előtt)

- `LiveSignalQualityAnalyzer` (ADR 0507) képkockánként mér — a pipeline
  eddig **csak jelentette** az állapotot, egyetlen sor sem reagált rá.
- `LiveQualityThresholds.standard`: `quietRmsDbfs = -40`, `loudPeakDbfs = -2`,
  `clippedRatioThreshold = 0,001`. **Nem mozdul.**
- `recognitionPreprocessingEnabled` (ADR 0542) létezik, mindenhol `false`,
  és a `lib/**`-ben **nem volt fogyasztója**.
- `ConfidenceCalibrationResolver` + `SelectivePredictionPolicy` (ADR 0536/0540)
  kész; **held-out artefaktum a fán nincs**, tehát minden sáv válasza ma
  `CalibrationUnavailableReason.noArtefact`.
- `live_pipeline.dart`: mindkét `calibratedConfidence` **hardkódolt `null`**
  — helyes érték, indoklás nélkül.
- Eszköz-profil: nem létezik; az 5+ telefonos A/B ember + hardver.

## 3. Scope

**Benne:** `QualityAwarePreprocessor` + `LivePreprocessingConfig`;
`DeviceAudioProfile`; a `LivePipeline` egyetlen előfeldolgozó hívási pontja +
a hozzá tartozó read-only getterek; `RecognitionCalibration` bekötés
sávonként egy hívási ponttal; selective-prediction verdikt kivezetése;
`RealStrumEngine` zászló-projekció (`bool`) és profil-átadás az izolátumnak;
barrel-export a `DeviceAudioProfile`-ra; tesztek; ADR + kör-brief + RAG chunk.

**Kívül:** BÁRMELY meglévő küszöb újrahangolása (`DspConfig`,
`LiveQualityThresholds`, margin-képlet, tonalness-kapu) — **egyetlen számjegy
sem változott**; a zászló-fájl (PKG-D); `domain/evaluation/**` és
`data/evaluation/**` (PKG-B); UI-képernyők és providerek (PKG-E/PKG-F);
ARB-kulcsok (a kör nem ad új felhasználói szöveget); DC-eltávolítás,
high-pass, noise-suppression (a terv §2 R31 opcionális elemei — mérés nélkül
nem indokolható újabb transzformáció a jelúton).

## 4. Érintett fájlok

| Fájl | Változás |
|---|---|
| `lib/features/live/engine/dsp/quality_aware_preprocessor.dart` | **ÚJ** — `LivePreprocessingConfig` (disabled/standard/tuned) + `QualityAwarePreprocessor` + `LivePreprocessingAdaptation` |
| `lib/features/live/domain/recognition/device_audio_profile.dart` | **ÚJ** — identity/measured/fromJson, hangos validáció |
| `lib/features/live/engine/dsp/recognition_calibration_wiring.dart` | **ÚJ** — `RecognitionCalibration` + `shippedChordEngineRevision` |
| `lib/features/live/engine/dsp/live_pipeline.dart` | előfeldolgozó hívási pont `addChunk`-ban; `preprocessing`/`deviceProfile`/`calibration` konstruktor-paraméterek; `chordCalibration`, `strumCalibration`, `strumSelectiveOutcome`, `chordSelectiveOutcome`, `selectivePredictionPolicy`, `preprocessingGainDb`, `preprocessingAdaptation`, `preprocessingClampedSampleCount` getterek; `reset()` bővítés |
| `lib/features/live/engine/real_strum_engine.dart` | `preprocessingEnabled` (bool, alap `false`) + `deviceProfile`; átadás az izolátumnak `_DspInit`-en át |
| `lib/features/live/public.dart` | `DeviceAudioProfile` export (a termelő másik feature-ben lesz) |
| `test/features/live/preprocessing/quality_aware_preprocessor_test.dart` | **ÚJ** — a fokozat egység-cellái |
| `test/features/live/preprocessing/live_preprocessing_test.dart` | **ÚJ** — pipeline-szintű paritás és kadencia |
| `test/features/live/dsp/live_calibration_wiring_test.dart` | **ÚJ** — kalibráció + selective prediction |
| `docs/adr/0552-…md`, `docs/rag/chunks/023-input-preprocessing.md` | doksi |

## 5. Kötött döntések

ADR 0552 D1–D9. Kiemelten: kikapcsolva **azonos lista-instancia** (D1); a
szintkorrekció csak a két SZINT-állapotra (D2); `clipping`-en **tartás, nem
reakció** (D3); a profil **fogyasztói seam**, identitás alapértékkel (D4); a
minőség-elemző a **nyers** jelet méri (D5); minden szám **MÉRETLEN**
alapérték, névvel (D6); sávonként **egy** kalibrációs hívási pont (D7); a
selective verdikt **csak jelentés** (D8); a clamp **számolt** (D9).

## 6. Acceptance criteria

| # | Kritérium | Státusz |
|---|---|---|
| 1 | Kikapcsolt állapotban a fokozat a hívó saját lista-instanciáját adja vissza | **PINNED-BY-TEST** — `quality_aware_preprocessor_test.dart` „hands back the caller's own list instance" |
| 2 | Kikapcsolt állapotban a pipeline minden kibocsátott képkockája bit-azonos, **mért eszközprofillal is** | **PINNED-BY-TEST** — `live_preprocessing_test.dart` „a disabled stage leaves every emitted frame bit-identical" |
| 3 | Bekapcsolva, 0 dB-es burkológörbével a jel változatlan (a korlát korlát) | **PINNED-BY-TEST** — „a zero-envelope policy runs, decides, and still changes nothing" |
| 4 | Az előfeldolgozás **nem tolja el az onset-/képkocka-időt** | **PINNED-BY-TEST** — „the stage never moves a frame in time" (kadencia + `engineTimeSec` azonosság); strukturális: a mintaóra a NYERS darabot számolja |
| 5 | `clipping` sosem indít új adaptációt (tart, nem reagál) | **PINNED-BY-TEST** — két cella (hidegindítás + felépült erősítés) |
| 6 | Mért RMS/peak nélkül nincs kitalált korrekció | **PINNED-BY-TEST** — „a level state with no measured RMS applies no level correction" |
| 7 | Slew-, boost/cut- és peak-headroom-korlát betartva; a clamp SZÁMOLT | **PINNED-BY-TEST** — 4 cella |
| 8 | A transzformáció egyetlen skalár/darab, vágás nélkül invertálható | **PINNED-BY-TEST** — „ONE scalar per chunk" + „exactly invertible" |
| 9 | `DeviceAudioProfile` hibás értékre hangosan bukik, JSON-körút fixpont | **PINNED-BY-TEST** — `measured()` refuses… + round-trip cella |
| 10 | Artefaktum nélkül `StrumPrediction.calibratedConfidence == null`, tipizált okkal | **PINNED-BY-TEST** — `live_calibration_wiring_test.dart` „no artefact: the confidence stays null and says WHY" |
| 11 | Artefaktum nélkül `ChordPrediction.calibratedConfidence == null`, tipizált okkal | **PINNED-BY-TEST** — „no artefact: calibratedConfidence stays null with a reason" |
| 12 | Held-out, modellre kötött teszt-artefaktummal **leképezett** érték jelenik meg mindkét sávon | **PINNED-BY-TEST** — 2 cella (`raw/2` leképezés) |
| 13 | Más súlyokra kötött, illetve in-sample artefaktum visszautasítva, okkal | **PINNED-BY-TEST** — 3 cella |
| 14 | A selective verdikt alapból `acceptAll`/`accept`, és szigorúbb házirend **nem** változtatja a kibocsátást | **PINNED-BY-TEST** — „a strict policy abstains in the REPORT and nowhere else" |
| 15 | „Degradált minőség → nő az abstention, nem a confidence" | **RÉSZBEN PINNED** — a mechanizmus él (kalibrálatlan konfidencia `requiresCalibration` házirend alatt **abstain**, teszttel rögzítve), de a szállított házirend `acceptAll`, mert egy szigorúbb küszöb **mért** kalibráció nélkül önkényes lenne |
| 16 | A −21 dBFS cél, a ±12 dB és az 1,5 dB/darab HELYES értékek | **NEEDS-MEASUREMENT** — 5+ telefonos A/B (ember + hardver), terv §2 R31 |
| 17 | AGC-detektálás valós eszközön | **NEEDS-MEASUREMENT** — a kör nem is kísérli meg |
| 18 | Van-e held-out kalibrációs artefaktum (a leképezett érték valós számai) | **NEEDS-MEASUREMENT** — `gh workflow run ml-train.yml -f sections="logo calib"` (E14-R21), chord-sáv: E14-R32 |
| 19 | Javít-e az előfeldolgozás a valós felismerésen | **NEEDS-MEASUREMENT** — a zászló ezért `false`; a végső predikátum a felhasználó valós gitáros APK-tesztje |

## 7. Verifikáció

Lokálisan **nem futtatható** (nincs Dart SDK). CI-ben érintett útvonalak:

```
test/features/live/preprocessing/
test/features/live/dsp/
```

A kör **nem állít sikeres verifikációt** (Ch14 §9/9): a fenti cellák a
megírt bizonyítékok, a zöld a CI-é.

## 8. Kockázatok

- **A fokozat bekapcsolva fantom-onsetet gyárthat**, ha az erősítés
  darabhatáron ugrik. Enyhítés: a slew-korlát (1,5 dB/darab, D6) és a
  `preprocessingGainDb` kivezetése; a zászló `false`, tehát a kockázat ma
  nem realizálódik.
- **A ±1,0 clamp veszteséges.** Enyhítés: `preprocessingClampedSampleCount`
  — nem nulla érték látható tény, nem elnyelt részlet (D9).
- **A `-21 dBFS` cél levezetés, nem illesztés.** Ha a valós eszközök
  eloszlása más, a fokozat rosszabb helyre visz. Enyhítés: a zászló és a
  `tuned()` sweep-konstruktor; mérés nélkül a fokozat nem kapcsolható be.
- **Elavult strum-kalibráció:** a `strumCalibration` a legutóbbi
  valószínűség-hordozó verdikté; a heurisztikus létra nem írja felül (annak
  nincs valószínűsége). Egy vegyes futás elméletileg elavult verdiktet
  jelenthet — a pipeline élettartama alatt az aktiváció nem vált, ezért ez ma
  nem realizálódik; dokumentálva a getteren.

## 10. Handoff

- **PKG-F (`lib/features/live/providers/live_providers.dart` tulajdonosa):**
  a zászló → motor bekötés az ő fájljában van, PKG-A nem nyúlt hozzá. A
  javasolt patch (fail-closed marad, amíg nem landol):

  ```dart
  // live_providers.dart, strumEngineProvider
  // + import '../../../app/config/app_config.dart';
  final engine = RealStrumEngine(
    mic: createMicCapture(ref, AudioOwner.live),
    mode: ref.watch(liveRecognitionModeProvider),
    preprocessingEnabled: ref
        .watch(appConfigProvider)
        .flags
        .recognitionPreprocessingEnabled,
  );
  ```

  (`appConfigProvider` a mért belépési pont — `lib/app/config/app_config.dart:213`,
  ugyanaz, amit az `app_router.dart` használ. A `deviceProfile` csak akkor
  adandó át, ha az E14-R14 varázsló már termel profilt — addig az identitás
  alapérték a helyes.)
- **E14-R14 (audio-setup varázsló):** a fogyasztói seam kész.
  `DeviceAudioProfile.measured(...)` a `features/live/public.dart` barrelről
  érhető el; a validáció **hangos** (NaN / üres id / ±12 dB fölötti offset /
  0 dBFS fölötti zajpadló → `ArgumentError`), tehát a varázslónak kezelnie
  kell a bukást, nem clampelnie.
- **PKG-B / E14-R21 + E14-R32:** amint egy held-out artefaktum landol, a
  bekötés kész — csak a `RecognitionCalibration`-t kell felépíteni a betöltött
  profilokból (`CalibrationArtefactLoader`), a hívási pontok nem változnak. A
  chord-sáv modell-kötése ma a `shippedChordEngineRevision` konstans; egy
  súlyfájllal bíró chord-motornak a valódi `chordModelSha256`-ot kell ide
  adnia.
- **Felhasználó:** a kör **nem változtat viselkedést** (zászló `false`,
  profil identitás, artefaktum nincs). A megnyíló mérések: 5+ telefonos
  device-A/B (R31) és a kalibrációs `ml-train.yml sections=calib` futás.
