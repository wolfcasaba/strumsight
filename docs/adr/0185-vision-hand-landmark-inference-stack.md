# ADR 0185 — Vision hand landmark inference stack

- **Státusz:** Elfogadva feltételesen (E05-R12 pre-flight, 2026-08-07); az
  asset-beszerzés és a natív bekötés **PENDING**, jövőbeli aktiváló kör dolga
- **Kör:** E05-R12 — Hand landmark provider adapter és model manifest
- **Implementer motor:** MiniMax M3 — az ADR-t az orchestrátor (Claude Sonnet 5)
  írta a pre-flightban (ADR 0055, pipeline-prompt §2)
- **Epic:** [Chapter 6 — Epic 5: Computer Vision](../sdd/06-epic-05-computer-vision.md)
  §15 (Hand landmark pipeline), §30 (Modellkezelés és manifest)
- **Kontext-ADR-ek:** [0063](0063-generated-ml-manifest-and-backend-ci.md)
  (generált ML manifest — audio-oldali precedens, MÁS bináris formátum),
  [0180](0180-vision-android-first-camera-strategy.md) (domain
  platform-függetlenség), [0179](0179-vision-capability-aware-feedback.md)
  (capability-aware feedback / `notObservable`)

## Kontextus

Az SDD Ch6 §15.1 egy providerfüggetlen kontraktust ír elő:

```dart
abstract interface class HandLandmarkProvider {
  String get modelId;
  String get modelVersion;
  Future<AppResult<void>> initialize(HandModelConfig config);
  Future<AppResult<HandLandmarkResult>> infer(VisionImage image);
  Future<void> close();
}
```

és a §403 sora tiltja, hogy a domain konkrét MediaPipe-, TFLite- vagy ML
Kit-API-tól függjön. A választott inference stack tehát a **`data/`-rétegbeli
production adapter** mögé kerül, a domain csak a stabil StrumSight
landmark ID-ket látja.

Három, ma mérhető korlát szűkíti a választást erre a körre:

1. **Az `allowed_paths` lista** (a kör-brief `ai-router` blokkja) nem
   tartalmaz egyetlen `assets/ml/*.tflite`/`*.task` bináris útvonalat sem, és
   egyetlen `android/`-alatti natív fájlt sem — kizárólag Dart-, JSON-,
   Python-generátor- és doksi-fájlokat.
2. **`native_gate = false`** ugyanabban a blokkban — ez a kör nem ad APK-építési
   bizonyítékot egy natív inference-útra.
3. **AGENTS.md §9** („Modell assethez checksum, model card, exportverzió és
   licence-adat tartozik") és a kör-brief §5.5 klauzulája: ha az asset jogtiszta
   beszerzése nem garantálható a kör környezetéből, a kör a kontraktot és a
   `RecordedHandLandmarkProvider` fixture-utat szállítja, a manifestben
   `status = "deferred"` bejegyzéssel.

E három együtt azt jelenti, hogy **ez a kör strukturálisan nem tud valódi natív
inference-t leszállítani**, függetlenül attól, hogy melyik stacket
választanánk — a kérdés csak az, MELYIK stack legyen a **jövőbeli aktiváló
kör** célja, és mi történjen a mai `NativeHandLandmarkProvider`-rel addig.

## Döntés

1. **Célstack a jövőbeli aktiváláshoz: `tflite_flutter` + a nyilvános
   MediaPipe Hands TFLite modellcsalád (Apache-2.0, palm-detector +
   hand-landmark kétlépcsős pipeline, 21 pont/kéz).** Indoklás: ez a pub.dev
   csomag a saját natív runtime-ját hozza, **nem igényel egyedi
   Android/iOS-natív kódot** az alkalmazás oldalán (szemben a MediaPipe Tasks
   API natív AAR-jával, ami Kotlin/Swift platform-channel kódot igényelne) —
   ezért ez az egyetlen jelölt, ami elméletben **beleférne** egy jövőbeli,
   csak Dart-/pubspec-szintű allowed_paths-ú körbe, natív fájlok nélkül is.
2. **Ez a kör NEM szerzi be, NEM tölti le és NEM pinneli a bináris assetet.**
   A `VisionModelManifest` egy `vision_models` bejegyzést kap
   `status = "deferred"` jelöléssel; a `NativeHandLandmarkProvider` erre a
   hiányra **fail-closed `unavailable`**-t ad, ezt teszt bizonyítja. Az asset
   tényleges forrása, licencszövege és checksuma egy **jövőbeli, saját ADR-
   kiegészítéssel** (vagy önálló ADR-rel) járó aktiváló kör dolga, amikor a
   redisztribúciós jóváhagyás is megtörtént.
3. **`pubspec.yaml` MOST ne kapjon inference pub-függőséget
   (`tflite_flutter`-t).** Egy asset nélküli, sehonnan nem hívott
   inference-függőség hamis haladás-látszatot keltene (a repo „no demos —
   valódi funkcionalitás" elve, `docs/LESSONS.md` L-korpusz). A függőség a
   jövőbeli aktiváló körrel együtt, a valódi assettel és checksummal egyszerre
   kerül be.
4. **Stabil, provider-független landmark ID topológia — 21 pont/kéz**, a
   nyilvánosan dokumentált MediaPipe Hands topológia szerint (a domain saját
   elnevezése, nem provider-index):
   `wrist`(0); `thumbCmc`/`thumbMcp`/`thumbIp`/`thumbTip`(1–4);
   `indexMcp`/`indexPip`/`indexDip`/`indexTip`(5–8);
   `middleMcp`/`middlePip`/`middleDip`/`middleTip`(9–12);
   `ringMcp`/`ringPip`/`ringDip`/`ringTip`(13–16);
   `pinkyMcp`/`pinkyPip`/`pinkyDip`/`pinkyTip`(17–20). Ez a lista a stabil
   StrumSight ID-halmaz, függetlenül attól, hogy végül melyik konkrét modell
   szolgáltatja a nyers koordinátákat (ADR 0180 §3 — a domain provider-index
   szivárgása NEM elfogadható).
5. **Falszifikálható újradöntési feltétel** (ADR 0184 mintáját követve): ha egy
   jövőbeli valós-eszközös mérés azt mutatja, hogy a `tflite_flutter`
   kétlépcsős CPU-inference nem tartja a device-mátrix
   (`docs/manual-testing/vision-device-matrix.md` §2.3) FPS/confidence
   küszöbét az elsődleges eszköztieren, a tartalék a **MediaPipe Tasks natív
   AAR-út** — ez saját, `android/`-t érintő és `native_gate = true` kört
   igényel, ezt a döntést nem írja felül hallgatólagosan.

## Következmények

- A `HandLandmarkProvider` interfész és a `HandLandmarks` domain-modell ebben a
  körben készül el és **stabil marad**, függetlenül attól, hogy melyik stack
  aktiválódik később (1–4. pont).
- A `RecordedHandLandmarkProvider` (fixture-alapú) a valódi CI-út, amíg a
  production adapter deferred — ez nem ideiglenes kompromisszum, hanem a
  brief §5.6 szerint **a végleges CI-stratégia** is (a natív inference-t a CI
  sosem futtatja).
- A device-mátrix `docs/manual-testing/vision-device-matrix.md` §2.3 sorai
  (jobb/bal kéz landmark, confidence/FPS) **már léteznek** az E05-R01
  sablonból — ez a kör nem módosítja a fájlt, a PENDING sorok már a helyükön
  vannak a jövőbeli aktiváláshoz.
- Az APK méretnövekedés kérdése (SDD §9 kockázat) **elhalasztva** a jövőbeli
  aktiváló körre — ma nincs bináris asset, tehát nincs mérhető növekedés sem.

## Elutasított alternatívák

- **Google ML Kit.** Elvetve: a termékkatalógusa (Barcode, Face
  Detection/Mesh, Image Labeling, Object Detection, **Pose Detection**,
  Selfie Segmentation, Text Recognition, Digital Ink) nem tartalmaz
  kéz-landmark/finger-tracking API-t — a Pose Detection csak test-ízületeket
  (váll, csukló mint egyetlen pont) ad, ujj-szintű landmarkot nem.
- **MediaPipe Tasks natív AAR MOST.** Elvetve: Kotlin/Android natív
  platform-channel kódot igényelne, ami kívül esik ennek a körnek az
  `allowed_paths` listáján, és sérti a `native_gate = false`-ot (1–3.
  kontextus-pont). Jövőbeli, saját körben újranyitható (5. pont).
- **Saját, nulláról tanított landmark-modell.** Elvetve: nincs annotált
  kéz-póz dataset a repóban; a MediaPipe publikus modellje már validált,
  license-tiszta kiindulópont, amint az asset-beszerzés jóváhagyást kap. A
  training ráadásul AGENTS.md §9 szerint normál fejlesztési körben tilos,
  hacsak a fejezet külön nem írja elő — a §15 nem írja elő.
- **Asset azonnali, felügyelet nélküli letöltése és bepinnelése ebben a
  körben.** Elvetve: pontosan az a kockázat, amit az AGENTS.md §9
  (checksum+model card+licence-adat kötelező) és a brief §5.5 klauzulája
  megelőzni igyekszik — egy harmadik féltől származó bináris redisztribúciós/
  licenc-jóváhagyás nélkül nem kerülhet be a repóba és a szállított APK-ba.
