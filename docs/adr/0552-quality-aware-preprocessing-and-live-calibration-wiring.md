# ADR 0552 — Minőség-tudatos bemeneti előfeldolgozás, eszköz-adaptációs seam és a kalibrációs profil élő bekötése

**Státusz:** elfogadva (2026-09-09) · **Kör:** E14-R31 (PKG-A, 2. hullám) ·
**Épít erre:** ADR 0507 (Live jelminőség), ADR 0536 (modell-kötött kalibrációs
artefaktum + selective prediction), ADR 0540 (chord-kalibráció), ADR 0542
(`recognitionPreprocessingEnabled` zászló), ADR 0545 (shadow-seam) ·
**Előkészíti:** E14-R14 (audio-setup varázsló), E14-R32 (chord-kalibráció
artefaktum)

## Kontextus (mért)

- `lib/features/live/engine/quality/live_signal_quality_analyzer.dart`
  (ADR 0507) képkockánként **mér**: `SignalQualitySnapshot` nyolc állapottal
  (`good`, `tooQuiet`, `tooLoud`, `clipping`, `tooNoisy`, `speechLike`,
  `unstable`, `unknown`) plusz `peakDbfs`/`rmsDbfs`/`noiseFloorDbfs`/…, minden
  metrika **nullable**, mert a „még nincs mérve" nem 0.
  A pipeline eddig **csak jelentette** ezt az állapotot; egyetlen sor sem
  reagált rá a jel szintjén.
- `LiveQualityThresholds.standard` mért kapui: `quietRmsDbfs = -40`,
  `loudPeakDbfs = -2`, `clippedRatioThreshold = 0,001`. Ezeket a kör **nem
  mozdítja**.
- `lib/app/config/feature_flags.dart:48` — `recognitionPreprocessingEnabled`
  létezik, alapértéke MINDEN környezetben `false`, és a `lib/**`-ben eddig
  **nem volt fogyasztója** (`grep` bizonyíték: csak a zászló-regiszter és a
  release-doksik hivatkozták).
- `lib/features/live/domain/evaluation/confidence_calibration_profile.dart`
  (ADR 0536) kész: `ConfidenceCalibrationResolver.calibrate` VAGY értéket ad,
  VAGY tipizált okot (`noArtefact`, `modelMismatch`, `bandMismatch`,
  `inSampleArtefact`). `selective_prediction.dart` `SelectivePredictionPolicy`
  + `applySelectivePolicy`. A fán **nincs held-out artefaktum**, ezért a
  szolgáltatható válasz ma minden sávon `noArtefact`.
- `live_pipeline.dart`-ban a `StrumPrediction.calibratedConfidence` és a
  `ChordPrediction.calibratedConfidence` **hardkódolt `null` literál** volt —
  helyes eredmény, de indoklás nélkül: a `null` nem hordozta, hogy MIÉRT
  nincs érték.
- Eszköz-profil: nem létezik. Az 5+ telefonos A/B (terv §2 R31) ember +
  hardver; ebben a konténerben nem futtatható.

## Döntés

### D1 — Az előfeldolgozás egy KIKAPCSOLT ÁLLAPOTBAN BIT-AZONOS fokozat

Új fokozat: `engine/dsp/quality_aware_preprocessor.dart`
(`LivePreprocessingConfig` + `QualityAwarePreprocessor`). A `LivePipeline`
egyetlen ponton hívja, `addChunk` elején, a jelminőség-mérés UTÁN.

A szállított állapot `LivePreprocessingConfig.disabled()`, és ilyenkor a
`process` a hívó **saját lista-INSTANCIÁJÁT** adja vissza (`identical`, nem
csak `==`). Így „ki van kapcsolva ⇒ bit-azonos" nem konvenció, hanem
azonosság — a lenti DSP-lánc nem is tudja megfigyelni, hogy a fokozat létezik.
A `RealStrumEngine` egy `bool`-t (a `recognitionPreprocessingEnabled` zászló
projekcióját) kap, nem a konfigot, hogy a zászlót olvasó provider soha ne
importáljon `engine/dsp/`-t.

### D2 — A szintkorrekció HATÓKÖRE a két SZINT-állapot

Szintnormalizálás CSAK `tooQuiet` és `tooLoud` állapotban indul. `tooNoisy`,
`speechLike`, `unstable` nem szint-probléma (egy zajos jelet hangosabbá tenni
a zajt teszi hangosabbá), az `unknown` pedig „még nincs mérve". A `switch`
**kimerítő, `default` ág nélkül**: egy jövőbeli `SignalQualityState`-nek itt
saját választ kell adni, nem örökölhet csendben egyet.

### D3 — `clipping` állapotban SOHA nincs új adaptáció

A clippelt jelből a levágott minták már hiányoznak: erősíteni a kárt
erősíti, halkítani nem hozza vissza őket. A `clipping` állapot ezért
**tartja** az aktuális erősítést (`clippingHold`), nem reagál rá. Ez a
mandátum („never on clipping") szó szerinti implementációja.

### D4 — `DeviceAudioProfile`: FOGYASZTÓI seam, identitás alapértékkel

`domain/recognition/device_audio_profile.dart` — kizárólag technikai
audio-route leírás (`profileId`, `inputGainOffsetDb`, `noiseFloorDbfs?`),
soha nem személy, szoba, képesség vagy helyszín (ADR 0224 §4 határ).
A szállított érték `DeviceAudioProfile.identity()`: 0 dB, **nincs** mért
zajpadló (`null`, nem egy hihetőnek látszó dBFS — ADR 0271 §1).

Ez a kör **nem ír profilt**. A szándékolt termelő az audio-setup varázsló
(E14-R14); ez a fájl a fogyasztói oldal, és azért kerül a `public.dart`
barrelre, mert a termelő egy MÁSIK feature-ben lesz, az `engine/dsp/` pedig
szándékosan nincs a barrelen.

`DeviceAudioProfile.measured` **hangosan bukik** (NaN, üres id, ±12 dB-en
túli offset, 0 dBFS fölötti zajpadló) ahelyett, hogy csendben clampelne: egy
hibás varázsló-számítás így nem detektálási regresszióként jelenik meg.

### D5 — A minőség-elemző mindig a NYERS jelet méri

`_signalQuality.addChunk(chunk)` a nyers darabot kapja, és csak utána fut az
előfeldolgozás. Ha a már korrigált jelet mérnénk, a szabályzókör önmagát
kergetné (a korrekció eltüntetné a saját bemenő jelét). A mintaszám sosem
változik, ezért az `_samplesSeen` mintaóra — és vele a képkocka-kadencia és
az `engineTimeSec` — az előfeldolgozástól **strukturálisan** független.

### D6 — Minden szám MÉRETLEN alapérték, és annak is van nevezve

| Konstans | Érték | Státusz |
|---|---:|---|
| `defaultTargetRmsDbfs` | −21 dBFS | **MÉRETLEN** — levezetés: a szállított kapuk (−40 dBFS RMS quiet, −2 dBFS peak loud) középpontja |
| `defaultMaxBoostDb` | +12 dB | **MÉRETLEN** biztonsági korlát (4× amplitúdó; fölötte az eszköz zajpadlója ugyanolyan gyorsan nő, mint a gitár) |
| `defaultMaxCutDb` | 12 dB | **MÉRETLEN**, szimmetrikus |
| `defaultMaxGainStepDb` | 1,5 dB / darab | **MÉRETLEN** — levezetés: a darabhatáron ugró erősítés lépcsőt tenne a jelbe, és a spektrális-fluxus onset-detektor pont lépcsőt keres (fantom-pengetés) |
| `defaultPeakHeadroomDb` | 1 dB | **MÉRETLEN** biztonsági korlát: a fokozat nem hozhat létre clippinget |
| `DeviceAudioProfile.maxInputGainOffsetDb` | ±12 dB | **MÉRETLEN** biztonsági korlát |

Ezek **burkológörbék, nem illesztett értékek**. Mérés szűkítheti őket;
mérés nélkül senki nem tágíthatja. A forrás és a levezetés a
`docs/rag/chunks/023-input-preprocessing.md`-ben él, ugyanabban a
változtatásban. Egyetlen meglévő küszöb (`DspConfig`, `LiveQualityThresholds`)
sem mozdul.

### D7 — A kalibrált konfidencia EGY hívási ponton, sávonként

`engine/dsp/recognition_calibration_wiring.dart` (`RecognitionCalibration`) a
bekötés: matematikát nem tartalmaz, csak PKG-B rezolvereit hívja. A
`live_pipeline.dart`-ban sávonként **pontosan egy** hívási pont van:

- strum: `_isDirectionConfirmed`, nyers pontszám `max(pDown, pUp)` — a NYERŐ
  IRÁNY valószínűsége. A `pNoStrum` az abstain-fejé, nem „mennyire biztos,
  hogy leütés volt";
- chord: a `chordCalibration` getter, amit a `chordPrediction` olvas, ezért a
  kettő nem tud eltérni egymástól.

A szállított fában mindkettő `null` marad — de a `null` mostantól a rezolver
**verdiktje** (`CalibrationUnavailableReason.noArtefact`), nem hardkódolt
literál. Érték csak HELD-OUT, modellre kötött artefaktumból jöhet: az
in-sample visszautasítás (ADR 0536 D2) a rezolveré, és ez a fájl soha nem
kerüli meg.

A chord-sáv modell-kötése a `shippedChordEngineRevision` NEVESÍTETT konstans
(`nnls-viterbi-dictionary-r176`), nem üres string — hogy egy jövőbeli,
súlyfájllal bíró chord-motort a típus KÉNYSZERÍTSEN a valódi
`chordModelSha256` átadására, ahelyett hogy csendben örökölné a szótáras
dekóderre illesztett leképezést.

### D8 — A selective prediction verdikt CSAK JELENTÉS

`strumSelectiveOutcome` / `chordSelectiveOutcome` / `selectivePredictionPolicy`
read-only getterek. Az alapértelmezett házirend
`SelectivePredictionPolicy.acceptAll` — a mai viselkedés identitása. **A
pipeline döntési útja nem olvassa őket**: `_isDirectionConfirmed` változatlanul
a `StrumPrediction.decision`-re támaszkodik, a chord-verdikt változatlanul a
latch/tonalness/jelminőség kapukra. Egy szigorúbb házirend telepítése tehát
azt változtatja meg, amit JELENTÜNK, nem azt, amit kibocsátunk — ez teszttel
rögzített.

### D9 — A ±1,0 biztonsági clamp SZÁMOLT, nem elnyelt

A fokozat egyetlen veszteséges lépése a ±1,0 vágás. A megcsapott minták
száma `preprocessingClampedSampleCount`-ként kivezetve: nem nulla érték azt
jelenti, hogy a boost-korlát és a peak-headroom nem fedte a valóságot, és ezt
valakinek látnia kell. Néma try/catch és néma veszteség nincs.

## Mit mér ez, és mit nem

| Állítás | Státusz |
|---|---|
| Kikapcsolva a fokozat a hívó saját listáját adja vissza | **TESZTTEL RÖGZÍTVE** (`quality_aware_preprocessor_test.dart`) |
| Kikapcsolva a pipeline minden kibocsátott képkockája azonos, mért eszközprofillal is | **TESZTTEL RÖGZÍTVE** (`live_preprocessing_test.dart`) |
| A 0 dB-es burkológörbe bekapcsolva is változatlanul hagyja a jelet | **TESZTTEL RÖGZÍTVE** |
| A fokozat nem tol el képkockát az időben | **TESZTTEL RÖGZÍTVE** (kadencia + `engineTimeSec` azonosság) |
| `clipping` sosem indít új adaptációt | **TESZTTEL RÖGZÍTVE** |
| Mért RMS nélküli szint-állapot nem tippel | **TESZTTEL RÖGZÍTVE** |
| A slew-korlát, a boost/cut korlát és a peak-headroom betartva | **TESZTTEL RÖGZÍTVE** |
| A clamp számolt, a transzformáció vágás nélkül invertálható | **TESZTTEL RÖGZÍTVE** |
| Artefaktum nélkül `calibratedConfidence == null` + `noArtefact` ok | **TESZTTEL RÖGZÍTVE** (`live_calibration_wiring_test.dart`) |
| Held-out, modellre kötött teszt-artefaktummal leképezett érték | **TESZTTEL RÖGZÍTVE** |
| Más súlyokra kötött / in-sample artefaktum visszautasítva, okkal | **TESZTTEL RÖGZÍTVE** |
| Szigorúbb házirend a JELENTÉST változtatja, a kibocsátást nem | **TESZTTEL RÖGZÍTVE** |
| **A −21 dBFS cél, a ±12 dB és az 1,5 dB/darab HELYES értékek-e** | **NEM MÉRT** — 5+ telefonos A/B kell (ember + hardver) |
| Az AGC-detektálás valós eszközön | **NEM MÉRT** — ez a kör nem is kísérli meg |
| Javít-e az előfeldolgozás a felismerésen | **NEM MÉRT** — a zászló ezért `false`, és a végső predikátum a valós gitáros APK-teszt |
| Van-e held-out kalibrációs artefaktum | **NINCS** — E14-R21/R32 mérése (`ml-train.yml sections=calib`) |

## Következmények

- A zászló `false`, az eszközprofil identitás, az artefaktum hiányzik ⇒ a
  szállított build viselkedése **változatlan**; a kör mechanizmust ad, nem
  hangolást.
- A visszagörgetés egyetlen zászló-billentés (`recognitionPreprocessingEnabled`
  → `false`), nem release — ahogy a `docs/release/ch14-recognition-rollout.md`
  §4 ígéri.
- A `strumEngineProvider` (PKG-F tulajdon) még **nem** olvassa a zászlót: a
  `RealStrumEngine.preprocessingEnabled` alapértéke `false`, tehát a jelenlegi
  fa fail-closed. A bekötés pontos patch-e a kör-brief §10-ében.
