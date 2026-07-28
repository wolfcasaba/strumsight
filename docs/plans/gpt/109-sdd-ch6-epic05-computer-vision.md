---
id: 109
topic: SDD Ch6 / Epic 5 — Computer Vision: 30 kör (kamera lifecycle, hand/pose landmark, gitárgeometria, audio-vision sync, false-feedback gate; exact fret = kísérleti)
tags: [sdd, epic5, vision, camera, landmarks, calibration, privacy, experimental]
status: active
depends_on: [105, 106]
canonical_target: docs/sdd/06-epic-05-computer-vision.md
verify: false technical feedback rate gate + valós eszközös benchmark
source: chatgpt-plan 2026-07-28 (Codex Execution Pack, 58-file manifest)
---

# StrumSight Software Design Document

## Chapter 6 — Epic 5: Computer Vision

**Dokumentumverzió:** 1.0  
**Implementációs állapot:** fejlesztésre kész  
**Repository:** `wolfcasaba/strumsight`  
**Előfeltétel:** Chapter 2 — Epic 1 Core Platform & Infrastructure  
**Előfeltétel:** Chapter 3 — Epic 2 Practice Engine  
**Kapcsolódó rendszer:** Chapter 4 — Epic 3 Song Trainer  
**Kapcsolódó rendszer:** Chapter 5 — Epic 4 AI Guitar Teacher  
**Célplatform:** Flutter, Android-first, később iOS  
**Fő képesség:** on-device kameraalapú gitártechnika-megfigyelés, bizonyíték-alapú visszajelzés és audio–vision szinkron  
**Végrehajtó:** Codex  
**Végrehajtási mód:** körönként, külön branchben, capability gate-ekkel, valós eszközös benchmarkkal és regressziós tesztekkel

---

# 1. Az Epic célja

Az Epic 5 célja egy olyan Computer Vision rendszer létrehozása, amely a telefon kamerájával megfigyelhető gitártechnikai jelenségeket helyben feldolgozza, strukturált bizonyítékká alakítja, majd ezt a Practice Engine, Song Trainer, Audio Analysis és AI Guitar Teacher számára biztonságosan elérhetővé teszi.

A rendszer nem „kamerás varázspontozó”. A cél egy mérhető, capability-aware vizuális coach, amely pontosan megkülönbözteti:

- mit látott a kamera;
- milyen modell vagy geometriai szabály alapján következtetett;
- milyen confidence tartozik az eredményhez;
- mi nem volt látható;
- melyik tanács megbízható;
- melyik megfigyelés csak kísérleti;
- mikor kell a felhasználót kameraáthelyezésre vagy újrakalibrálásra kérni.

Az Epic végére a felhasználó legyen képes:

- a telefonját egy vezetett setup segítségével megfelelő helyre állítani;
- elvégezni a kamera-, test-, kéz- és gitárkalibrációt;
- valós időben látni, hogy a bal vagy jobb kéz követése aktív-e;
- vizuális visszajelzést kapni a megfigyelhető csukló-, kéz- és testtartási mintákról;
- célzott Vision Practice gyakorlatot indítani;
- egy gyakorlás után rövid, bizonyítékokra épülő technikai összefoglalót kapni;
- megtekinteni, hogy melyik feedback milyen frame-ekből és metrikából származott;
- kikapcsolni a kameraalapú elemzést úgy, hogy minden audiofunkció továbbra is működjön;
- törölni minden lokálisan mentett vizuális session-adatot;
- raw kép- vagy videómentés nélkül használni az alapfunkciókat.

A rendszer elsődleges célja nem az exact string/fret recognition. A gitárnyak, ujjak és húrok perspektivikus, takart, eltérő fényű és eltérő hangszerű képei miatt ez külön, kísérleti capability. Az MVP kötelező képessége a megbízhatóbb, nagyobb léptékű technikai megfigyelés:

- kéz és csukló relatív helyzete;
- kézmozgás pályája;
- jobb kéz pengetési zónája;
- stroke amplitúdó és iránykonzisztencia;
- testtartás és vállszimmetria;
- gitárnyak és kéz relatív geometriája;
- láthatóság, blur, fény és occlusion minőség;
- audioesemények és vizuális mozgás időbeli kapcsolata.

A rendszer nem adhat biztos diagnózist olyan jelenségről, amely nincs megfelelően látható. Különösen tilos:

- ujjtartást állítani, ha az ujjhegyek takarásban vannak;
- exact fret/string hibát állítani alacsony geometriai confidence mellett;
- fájdalom vagy sérülés okát diagnosztizálni;
- testalkatból, bőrszínből, életkorból vagy más érzékeny jellemzőből következtetni;
- raw videót automatikusan feltölteni;
- kameraengedély hiányát gyakorlási hibaként kezelni.

---

# 2. Termékvízió

## 2.1 Felhasználói ígéret

> Tedd le a telefont, kezdj el játszani, és a StrumSight csak arról adjon visszajelzést, amit valóban látott és hallott.

A Computer Vision modul a gitáros számára nem egy újabb bonyolult stúdióeszköz. A felhasználói élmény három lépésből áll:

1. **Állítsd be:** a rendszer megmutatja, hova kerüljön a telefon és mi legyen látható.
2. **Játssz:** a kamera és az audio engine együtt, helyben figyel.
3. **Javíts egy dolgot:** a rendszer egy vagy két nagy hatású, mérhető technikai fókuszt ad.

## 2.2 Nem a skeleton overlay a termék

Egy kézcsontváz kirajzolása önmagában nem gitároktatás. A termékérték akkor jön létre, ha a rendszer:

- gitárspecifikus koordinátarendszerbe helyezi a kézpontokat;
- időben stabilizálja a megfigyelést;
- elkülöníti a valódi technikai mintát a kamera jitterétől;
- összeveti a mozgást az audioeseményekkel;
- a mérést tanítható, rövid feedbackké alakítja;
- nem ad feedbacket, amikor a mérés nem elég biztos.

## 2.3 Kamera mint opcionális érzékelő

A StrumSight továbbra is offline, audio-first alkalmazás. A Computer Vision:

- külön engedélyt kér;
- feature flaggel kikapcsolható;
- nem akadályozhatja a Live, Tuner, Analyze, Practice vagy Song Trainer audiofunkcióit;
- nem lehet kötelező onboarding lépés;
- kamera nélküli eszközön vagy tiltott permission mellett graceful fallbacket ad;
- nem módosíthatja a meglévő audio scoringot, csak kiegészítő evidence-et adhat.

## 2.4 Bizonyíték-alapú coaching

Minden vizuális feedbackhez tartozzon:

- metrikaazonosító;
- mért időablak;
- confidence;
- láthatósági minőség;
- szükséges capability;
- feedback policy verzió;
- opcionális frame-reference, amely nem tartalmaz raw képet;
- rövid indoklás;
- javasolt következő gyakorlat.

A rendszer különítse el a következő állításokat:

```text
MEASURED       — közvetlenül számított geometriai vagy időbeli metrika
INFERRED       — több mérésből képzett technikai következtetés
NOT_OBSERVABLE — a kameraállás vagy takarás miatt nem állapítható meg
EXPERIMENTAL   — még nem production-grade capability
```

---

# 3. Kapcsolat a jelenlegi kódbázissal

## 3.1 Meglévő, újrahasználandó képességek

A repository jelenleg nem tartalmaz kamera- vagy vision feature-t, de az alábbi működő elemekre lehet építeni:

- Flutter és Riverpod alkalmazás;
- GoRouter navigáció;
- Android-first platformstruktúra és iOS projekt;
- `permission_handler`, jelenleg mikrofonengedélyhez;
- alkalmazás-lifecycle és auto-dispose minták;
- on-device audio capture;
- valós idejű chord- és strum-direction detection;
- monotonic audio engine time és discrete strum sequence;
- Learn/Practice session scoring;
- metronóm és latency calibration;
- Analyze clip pipeline;
- Songs és Setlists;
- Progress és Streak;
- AI Tutorhoz tervezett structured evidence és tool boundary;
- kiterjedt unit, widget, property és real-audio tesztkészlet;
- Android Java 17, hardware acceleration és modern Flutter embedding;
- iOS 13 deployment target.

A jelenlegi `pubspec.yaml` nem tartalmaz camera vagy vision inference dependencyt. Az Android manifest csak mikrofon-, internet- és notification permissiont deklarál. Az iOS `Info.plist` csak mikrofon usage descriptiont tartalmaz. Ezért a kamera bevezetése külön platform-, privacy- és lifecycle-migrációt igényel.

## 3.2 Jelenlegi korlátok

Az Epic kezdetén:

1. Nincs `CAMERA` permission.
2. Nincs `NSCameraUsageDescription`.
3. Nincs camera service vagy camera session coordinator.
4. Nincs frame stream absztrakció.
5. Nincs rotation, mirror és crop normalizálás.
6. Nincs camera quality assessor.
7. Nincs visual calibration.
8. Nincs hand landmark provider.
9. Nincs pose landmark provider.
10. Nincs guitar/fretboard geometry.
11. Nincs audio–vision clock mapping.
12. Nincs vision session state machine.
13. Nincs vision evidence schema.
14. Nincs vizuális feedback policy.
15. Nincs camera privacy settings.
16. Nincs device capability benchmark.
17. Nincs model manifest vagy CV model evaluation.
18. Nincs vision dataset és annotation policy.
19. Nincs camera-aware Practice vagy Song Trainer mód.
20. Az AI Tutor jelenleg nem kaphat megbízható vizuális evidence-et.

## 3.3 Kapcsolat a Core Platformhoz

A Chapter 2 után rendelkezésre kell állnia:

- validált AppConfignak;
- feature flageknek;
- AppResult és AppFailure modelleknek;
- strukturált loggernek;
- platform permission gateway mintának;
- lifecycle koordinációnak;
- verziózott storage-nak;
- model manifest és CI integrity gate alapnak.

A Vision feature csak ezekre épülhet. Nem hozhat létre párhuzamos, feature-specifikus logging-, permission- vagy storage-rendszert.

## 3.4 Kapcsolat a Practice Engine-hez

A Vision Practice nem külön mini-alkalmazás. A Chapter 3 sessionmodelljét használja, és vizuális observationt ad a meglévő gyakorlatokhoz.

Példák:

- open-string strumming: jobb kéz stroke konzisztencia;
- chord change: bal kéz mozgásgazdaságosság és ready-position idő;
- speed builder: technikai forma romlásának detektálása tempónként;
- muted rhythm: pengetési pálya és beat alignment;
- posture warm-up: váll-, könyök- és csukló baseline.

A vision feedback nem írhatja felül az audio hit/miss eredményt. Külön dimensionként kerül a session resultba.

## 3.5 Kapcsolat a Song Trainerhez

A Song Trainer használhatja a Vision rendszert:

- problémás szakasz technikai megfigyelésére;
- A–B loop alatt mozgáskonzisztencia mérésére;
- chord change előkészítési idő megfigyelésére;
- jobb kéz stroke economy mérésére;
- performance mode-ban opcionális, alacsony terhelésű trackingre.

A backing track és a kamera egyszerre növeli a CPU-, memória- és hőterhelést. Ezért a Song Trainer integráció csak device tier és thermal policy mellett aktiválható.

## 3.6 Kapcsolat az AI Guitar Teacherhez

A tutor csak strukturált `VisionEvidence` objektumot kaphat. Tilos raw frame-et vagy videót automatikusan a model gatewayhez küldeni.

A tutor állíthatja például:

- „A jobb kéz pengetési pályája a session második felében nagyobb lett.”
- „A csuklóhelyzetet 82%-os confidence mellett tudtam követni.”
- „A bal kéz ujjhegyei többnyire takarásban voltak, ezért exact fret feedbacket nem adok.”

A tutor nem állíthat vizuális hibát olyan evidence nélkül, amely:

- production capabilityből származik;
- eléri a feedback policy küszöbét;
- tartalmaz visibility qualityt;
- nem lejárt vagy más sessionből való.

## 3.7 Kapcsolat az Audio Analysis 2.0-hoz

A Vision session eredmény opcionálisan kapcsolható egy `AnalysisDocument` dokumentumhoz. A két rendszer közös időalapot és session ID-t használjon.

A vizuális dimenziók külön jelenjenek meg:

- posture;
- left-hand economy;
- right-hand consistency;
- visibility quality;
- technique stability.

Az összpontszámba csak külön termékdöntés és validáció után kerülhetnek. Az első release-ben insight és trend formájában jelenjenek meg.

---

# 4. Az Epic hatóköre

## 4.1 Az Epic része

- Vision feature boundary;
- camera permission és lifecycle;
- platformfüggetlen camera contract;
- camera preview és frame stream;
- frame timestamp, rotation és mirror normalizálás;
- camera setup wizard;
- lighting, blur, framing és occlusion quality;
- handedness és instrument orientation;
- hand landmark inference adapter;
- pose landmark inference adapter;
- temporal tracking és smoothing;
- gitárnyak ROI és manual anchor calibration;
- fretboard coordinate system;
- opcionális automated neck detector decision gate;
- left-hand geometry metrics;
- right-hand movement metrics;
- posture metrics;
- audio–vision time synchronization;
- VisionEvidence és VisionInsight;
- vision session state machine;
- realtime overlay;
- feedback throttling;
- Practice Engine integráció;
- Song Trainer integráció;
- AI Tutor evidence adapter;
- Audio Analysis evidence adapter;
- lokális persistence;
- privacy és deletion;
- device tier és thermal degradation;
- model manifest;
- dataset és annotation specification;
- evaluation harness;
- feature flagek és staged rollout;
- Android-first production implementáció;
- iOS contract és későbbi parity előkészítése.

## 4.2 Az Epic nem tartalmazza

- felhőben futó videóelemzést;
- automatikus videófeltöltést;
- közösségi videófeedet;
- videós órarögzítést;
- arcfelismerést;
- személyazonosítást;
- emotion detectiont;
- életkor-, nem- vagy etnikai következtetést;
- egészségügyi diagnózist;
- minden gitártípusra garantált exact string/fret felismerést;
- akkordfelismerés teljes kiváltását kamerával;
- 3D kézrekonstrukciót több kamerából;
- AR szemüveg támogatást;
- automatikus videóvágást vagy social exportot;
- cloud model traininget a felhasználó tudta nélkül.

## 4.3 Kísérleti hatókör

Az alábbi képességek csak `experimentalVision` feature flag mögött indulhatnak:

- exact fret index becslés;
- exact string assignment;
- finger-to-string contact;
- thumb-behind-neck klasszifikáció;
- palm mute detektálás;
- pick grip klasszifikáció;
- barre chord ujjkontaktus;
- bend és vibrato vizuális amplitúdó;
- automatikus guitar neck object detector.

Ezek nem számíthatnak bele kötelező scoringba, amíg nincs:

- reprezentatív evaluation dataset;
- eszköz- és fényteszt;
- bal- és jobbkezes parity;
- false feedback rate gate;
- confidence calibration;
- felhasználói opt-in.

---

# 5. Kötelező tervezési alapelvek

## 5.1 Privacy by default

- A frame-ek alapértelmezetten csak memóriában élnek.
- A Vision Engine feldolgozás után azonnal elengedi a frame buffer referenciáját.
- Raw fotó vagy videó nem kerül persistence-be.
- Debug frame capture kizárólag Lab buildben, explicit felhasználói művelettel engedélyezhető.
- A kamera preview külön UI-jelzést kap.
- A rendszer háttérben nem használhat kamerát.
- App pause vagy route leave esetén a kamera azonnal leáll.

## 5.2 Capability-aware feedback

A rendszer ne egyetlen `visionAvailable` booleant használjon. Képességenként szükséges státusz:

```text
unavailable
initializing
available
availableDegraded
experimental
blockedByPermission
blockedBySetup
blockedByDevice
failed
```

Minden insight deklarálja a minimális capabilityt.

## 5.3 Latest-frame processing

Realtime módban a pipeline ne építsen korlátlan frame queue-t. Ha az inference lassabb a kameránál:

- a legfrissebb frame maradjon meg;
- a köztes frame-ek eldobhatók;
- a timestamp folytonossága maradjon meg;
- a dropped frame count mérendő;
- az UI ne várjon régi frame feldolgozására.

## 5.4 Graceful degradation

A rendszer képes legyen fokozatosan csökkenteni a terhelést:

1. overlay rajzolási frekvencia csökkentése;
2. pose pipeline ritkítása;
3. hand pipeline FPS csökkentése;
4. model input resolution csökkentése;
5. csak egy kéz követése;
6. csak quality monitor futtatása;
7. vision leállítása, audio megtartása.

## 5.5 No feedback is better than false feedback

Ha a confidence, visibility vagy calibration quality nem elegendő:

- ne adj negatív technikai feedbacket;
- jelezd, hogy a mérés bizonytalan;
- adj setup-javaslatot;
- ne csökkents pontszámot;
- ne készíts hosszú távú skill evidence-et.

## 5.6 Determinisztikus policy a generatív szöveg előtt

A vision model observationt ad. A feedback kiválasztását elsőként determinisztikus policy végezze. Az AI Tutor később megfogalmazhatja vagy elmagyarázhatja, de nem találhat ki új vision claimet.

## 5.7 Model-provider függetlenség

A domain ne függjön konkrét MediaPipe-, TFLite-, ML Kit- vagy natív modell API-tól. Minden inference provider interfészt implementáljon.

## 5.8 Tesztelhető koordinátageometria

A perspektíva-, tükör-, crop- és orientation transzformációk pure Dart függvények legyenek, fixture-rel és property testtel védve.

---

# 6. Felhasználói történetek

## 6.1 Első beállítás

**Mint gitáros**, szeretném látni, hova tegyem a telefont, hogy a rendszer megbízhatóan lássa a kezemet és a gitárt.

Elfogadási elvárás:

- a setup overlay egyértelmű;
- jelzi, hogy melyik kéz vagy testrész hiányzik;
- fény- és blur problémát külön jelez;
- a felhasználó kihagyhatja;
- nincs automatikus felvételmentés.

## 6.2 Jobb kéz coach

**Mint kezdő vagy középhaladó gitáros**, szeretném tudni, hogy túl nagy-e a pengetési mozgásom, illetve következetes-e a stroke pályája.

A rendszer csak akkor ad feedbacket, ha:

- a pengető kéz látható;
- a gitártest vagy pengetési zóna kalibrált;
- elegendő stroke esemény történt;
- az audio és a vision eventek időben összerendelhetők.

## 6.3 Bal kéz coach

**Mint gitáros**, szeretném észrevenni, ha a csuklóm tartósan túl nagy szögben áll, vagy a kéz minden akkordváltásnál feleslegesen messz eltávolodik a nyaktól.

A rendszer ne állítsa, hogy konkrét ujj rossz húrt fog, ha a húr és az ujjkontaktus nem látható megbízhatóan.

## 6.4 Testtartás

**Mint hosszabban gyakorló felhasználó**, szeretném látni, ha a vállam vagy felsőtestem tartósan aszimmetrikusabb lett a session végére.

A feedback legyen semleges és nem orvosi:

- „A jobb vállad a session második felében magasabban maradt.”
- ne: „Ez vállsérülést fog okozni.”

## 6.5 Vision nélküli használat

**Mint privacy-érzékeny felhasználó**, szeretném teljes értékűen használni a StrumSightot kamera nélkül.

Minden audiofeature működjön változatlanul.

---

# 7. Vision capability modell

## 7.1 Capability szintek

```dart
sealed class VisionCapabilityLevel {
  const VisionCapabilityLevel();
}

final class VisionUnavailable extends VisionCapabilityLevel {}
final class CameraQualityOnly extends VisionCapabilityLevel {}
final class BodyAndHandTracking extends VisionCapabilityLevel {}
final class GuitarRelativeTracking extends VisionCapabilityLevel {}
final class TechniqueObservation extends VisionCapabilityLevel {}
final class ExperimentalFineGrainedFretting extends VisionCapabilityLevel {}
```

Termékértelmezés:

- **L0 — nincs kamera vagy permission:** támogatott fallback.
- **L1 — framing, fény, blur és presence:** kötelező MVP.
- **L2 — kéz- és test-landmark tracking:** kötelező MVP.
- **L3 — gitárhoz relatív kézgeometria:** kötelező MVP.
- **L4 — technikai observation és insight:** kötelező MVP, metrikánként gate-elve.
- **L5 — exact fret/string/contact:** kísérleti.

## 7.2 Capability report

```dart
final class VisionCapabilityReport {
  const VisionCapabilityReport({
    required this.camera,
    required this.handTracking,
    required this.poseTracking,
    required this.guitarGeometry,
    required this.audioVisionSync,
    required this.deviceTier,
    required this.reasons,
  });

  final CapabilityState camera;
  final CapabilityState handTracking;
  final CapabilityState poseTracking;
  final CapabilityState guitarGeometry;
  final CapabilityState audioVisionSync;
  final VisionDeviceTier deviceTier;
  final List<VisionCapabilityReason> reasons;
}
```

A report frissülhet session közben, például thermal degradation vagy elvesztett kalibráció miatt.

---

# 8. Célarchitektúra

```text
lib/
├── core/
│   ├── camera/
│   │   ├── camera_capture.dart
│   │   ├── camera_controller.dart
│   │   ├── camera_frame.dart
│   │   ├── camera_format.dart
│   │   ├── camera_permission.dart
│   │   ├── camera_session_coordinator.dart
│   │   ├── camera_timestamp.dart
│   │   └── camera_transform.dart
│   ├── ml/
│   │   ├── model_manifest.dart
│   │   ├── inference_backend.dart
│   │   └── device_acceleration.dart
│   └── geometry/
│       ├── point2.dart
│       ├── line2.dart
│       ├── polygon2.dart
│       ├── homography.dart
│       └── smoothing.dart
│
├── features/
│   └── vision/
│       ├── domain/
│       │   ├── vision_session.dart
│       │   ├── vision_observation.dart
│       │   ├── vision_evidence.dart
│       │   ├── vision_insight.dart
│       │   ├── vision_capability.dart
│       │   ├── camera_calibration.dart
│       │   ├── guitar_geometry.dart
│       │   ├── hand_landmarks.dart
│       │   ├── pose_landmarks.dart
│       │   ├── technique_metric.dart
│       │   └── vision_repository.dart
│       ├── application/
│       │   ├── vision_session_controller.dart
│       │   ├── setup_controller.dart
│       │   ├── calibration_controller.dart
│       │   ├── observation_fusion.dart
│       │   ├── feedback_policy.dart
│       │   └── vision_providers.dart
│       ├── data/
│       │   ├── camera/
│       │   ├── landmarks/
│       │   ├── guitar/
│       │   ├── persistence/
│       │   └── native/
│       ├── presentation/
│       │   ├── screens/
│       │   ├── widgets/
│       │   └── overlays/
│       └── public.dart
│
├── integrations/
│   ├── practice_vision_adapter.dart
│   ├── song_vision_adapter.dart
│   ├── tutor_vision_adapter.dart
│   └── analysis_vision_adapter.dart
│
android/app/src/main/kotlin/.../vision/
ios/Runner/Vision/
assets/vision/
ml/vision/
test/features/vision/
integration_test/vision/
```

## 8.1 Rétegszabályok

- A domain nem importálhat Fluttert, camera plugint vagy natív modell API-t.
- A presentation nem dolgozhat raw pixel bufferrel.
- A native adapter nem adhat vissza platform-specifikus típust a domainnek.
- A Practice, Song, Tutor és Analysis csak a `vision/public.dart` API-t importálhatja.
- A frame buffer nem kerülhet Riverpod state-be.
- A provider state csak immutable summaryt és session statuszt tartalmazhat.
- A nagy model outputokat streamen vagy belső pipeline-on kell továbbítani.

---

# 9. Domainmodell

## 9.1 VisionSessionId és FrameId

```dart
extension type VisionSessionId(String value) {}
extension type VisionFrameId(int value) {}
```

A frame ID monoton nő a sessionön belül. Nem azonos a kamera driver buffer indexével.

## 9.2 CameraFrameMetadata

```dart
final class CameraFrameMetadata {
  const CameraFrameMetadata({
    required this.frameId,
    required this.captureTimestampUs,
    required this.width,
    required this.height,
    required this.rotationDegrees,
    required this.mirrored,
    required this.pixelFormat,
    required this.cropRegion,
  });

  final VisionFrameId frameId;
  final int captureTimestampUs;
  final int width;
  final int height;
  final int rotationDegrees;
  final bool mirrored;
  final CameraPixelFormat pixelFormat;
  final NormalizedRect cropRegion;
}
```

A `captureTimestampUs` monotonic forrásból származzon. Wall clock nem használható audio–vision szinkronhoz.

## 9.3 Landmark modellek

```dart
final class LandmarkPoint {
  const LandmarkPoint({
    required this.id,
    required this.position,
    required this.visibility,
    required this.presence,
  });

  final String id;
  final Point3 position;
  final double visibility;
  final double presence;
}

final class TrackedHand {
  const TrackedHand({
    required this.trackId,
    required this.handedness,
    required this.landmarks,
    required this.confidence,
    required this.timestampUs,
  });

  final int trackId;
  final Handedness handedness;
  final List<LandmarkPoint> landmarks;
  final double confidence;
  final int timestampUs;
}
```

A modell által becsült handedness nem írhatja felül automatikusan a felhasználó `leftHandedMode` beállítását. A gitárkéz szerepét a felhasználói profil és a kalibráció határozza meg.

## 9.4 GuitarGeometry

```dart
final class GuitarGeometry {
  const GuitarGeometry({
    required this.neckCenterLine,
    required this.neckPolygon,
    required this.bodyAnchor,
    required this.bridgeAnchor,
    required this.nutAnchor,
    required this.orientation,
    required this.confidence,
    required this.source,
  });

  final Line2 neckCenterLine;
  final Polygon2 neckPolygon;
  final Point2 bodyAnchor;
  final Point2 bridgeAnchor;
  final Point2 nutAnchor;
  final GuitarOrientation orientation;
  final double confidence;
  final GuitarGeometrySource source;
}
```

Lehetséges source:

```text
manualCalibration
automaticDetector
trackedFromCalibration
hybrid
unavailable
```

## 9.5 VisionObservation

Observation a pipeline nyers, de normalizált kimenete. Nem felhasználói feedback.

```dart
sealed class VisionObservation {
  const VisionObservation({
    required this.timestampUs,
    required this.confidence,
    required this.quality,
  });

  final int timestampUs;
  final double confidence;
  final ObservationQuality quality;
}
```

Példák:

- `HandPoseObservation`;
- `BodyPoseObservation`;
- `GuitarGeometryObservation`;
- `StrokeMotionObservation`;
- `WristGeometryObservation`;
- `PostureObservation`;
- `FrameQualityObservation`;
- `OcclusionObservation`.

## 9.6 VisionEvidence

```dart
final class VisionEvidence {
  const VisionEvidence({
    required this.id,
    required this.metric,
    required this.window,
    required this.value,
    required this.unit,
    required this.confidence,
    required this.capability,
    required this.provenance,
    required this.observability,
  });

  final String id;
  final VisionMetricId metric;
  final TimeWindow window;
  final double value;
  final String unit;
  final double confidence;
  final VisionCapabilityId capability;
  final VisionProvenance provenance;
  final ObservabilityState observability;
}
```

## 9.7 VisionInsight

```dart
final class VisionInsight {
  const VisionInsight({
    required this.code,
    required this.severity,
    required this.priority,
    required this.evidenceIds,
    required this.feedbackPolicyVersion,
    required this.confidence,
    required this.action,
  });

  final String code;
  final InsightSeverity severity;
  final int priority;
  final List<String> evidenceIds;
  final String feedbackPolicyVersion;
  final double confidence;
  final VisionSuggestedAction action;
}
```

A `code` lokalizált szövegre fordul. A domain nem tartalmaz angol UI-mondatot.

## 9.8 VisionSessionResult

```dart
final class VisionSessionResult {
  const VisionSessionResult({
    required this.schemaVersion,
    required this.sessionId,
    required this.startedAt,
    required this.duration,
    required this.capabilities,
    required this.qualitySummary,
    required this.metrics,
    required this.insights,
    required this.performance,
    required this.modelVersions,
  });

  final int schemaVersion;
  final VisionSessionId sessionId;
  final DateTime startedAt;
  final Duration duration;
  final VisionCapabilityReport capabilities;
  final VisionQualitySummary qualitySummary;
  final List<VisionMetricSummary> metrics;
  final List<VisionInsight> insights;
  final VisionPerformanceSummary performance;
  final Map<String, String> modelVersions;
}
```

A result nem tartalmaz raw image-et, videót vagy biometrikus template-et.

---

# 10. Vision session state machine

```text
idle
  ↓
checkingCapability
  ↓
requestingPermission
  ↓
initializingCamera
  ↓
setupRequired ──→ calibrating
  ↓                  ↓
ready ←──────────────┘
  ↓
running ↔ paused
  ↓
finalizing
  ↓
completed
```

Hiba- és degradációs állapotok:

```text
permissionDenied
permissionPermanentlyDenied
cameraUnavailable
cameraBusy
setupInvalid
calibrationLost
degraded
thermalLimited
inferenceFailed
cancelled
disposed
```

## 10.1 Állapotinvariánsok

- `running` állapot csak érvényes camera lease mellett lehetséges.
- `running` állapotban pontosan egy frame consumer pipeline aktív.
- `paused` állapotban camera preview opcionálisan maradhat, inference nem.
- `disposed` után új callback nem módosíthat state-et.
- route leave után legfeljebb a következő lifecycle tickig minden camera resource felszabadul.
- `completed` result csak egyszer emitálható.
- calibration loss nem eredményezhet automatikusan negatív insightot.

## 10.2 Cancel és retry

A felhasználó megszakíthatja:

- permission request előtti flow-t;
- setupot;
- calibrationt;
- sessiont;
- finalizálást.

Retry új camera sessiont hozzon létre. Ne használjon hibás, félig dispose-olt controller példányt.

---

# 11. Kamera capture és platformstratégia

## 11.1 Platformfüggetlen contract

```dart
abstract interface class CameraCapture {
  Future<AppResult<List<CameraDevice>>> availableDevices();
  Future<AppResult<CameraSessionHandle>> open(CameraOpenRequest request);
}

abstract interface class CameraSessionHandle {
  Stream<CameraFrame> get frames;
  Stream<CameraSessionEvent> get events;
  CameraSessionInfo get info;
  Future<AppResult<void>> pauseAnalysis();
  Future<AppResult<void>> resumeAnalysis();
  Future<AppResult<void>> close();
}
```

## 11.2 Android

Az Android implementáció elsődleges célja lifecycle-bound camera preview és image-analysis stream. Kötelező:

- backpressure strategy latest-frame mód;
- YUV frame preferálása, ha a modell támogatja;
- analyzer callbacken belüli gyors buffer release;
- frame copy minimalizálása;
- rotation metadata megőrzése;
- front/back camera support;
- torch és exposure csak explicit setup opcióként;
- camera switch csak session restarttal;
- camera resource release app pause esetén.

## 11.3 iOS

Az iOS adapter contractja ugyanaz. Kötelező tervezési elv:

- natív pixel buffer preferálása;
- fölösleges BGRA konverzió kerülése;
- serial sample buffer queue;
- late frame discard;
- orientation és mirroring explicit kezelése;
- session interruption eventek továbbítása.

Az Epic Android-first. iOS production parity külön rollout gate, de a Dart domain és application réteg már platformsemleges legyen.

## 11.4 Flutter camera plugin döntés

Elsőként hivatalosan támogatott Flutter camera megoldást kell spike-ban mérni. Ha a plugin frame streamje, timestampje, pixel formatja vagy lifecycle-kezelése nem elég a követelményekhez, megengedett egy vékony saját platform plugin.

Tilos azonnal nagy natív camera frameworköt építeni mérés nélkül.

A döntés ADR-ben tartalmazza:

- init latency;
- preview stabilitás;
- frame timestamp minőség;
- YUV hozzáférés;
- memory copy szám;
- CameraX/AVFoundation viselkedés;
- Android device quirks;
- iOS interruption handling;
- tesztelhetőség.

---

# 12. Kameraengedély és privacy UX

## 12.1 Permission gateway

A Chapter 2 permission mintáját kell bővíteni:

```dart
abstract interface class CameraPermissionGateway {
  Future<CameraPermissionState> currentState();
  Future<CameraPermissionState> request();
  Future<AppResult<void>> openSettings();
}
```

Állapotok:

```text
granted
denied
permanentlyDenied
restricted
unavailable
```

## 12.2 Permission szöveg

A platform permission szöveg egyértelműen mondja ki:

- a kamera a gitártechnika helyi elemzéséhez kell;
- az alapfunkciók kamera nélkül működnek;
- raw videó alapértelmezetten nem kerül mentésre vagy feltöltésre.

## 12.3 In-app privacy panel

A Vision setup előtt jelenjen meg rövid panel:

- „Feldolgozás az eszközön”;
- „Nincs automatikus videómentés”;
- „Bármikor leállítható”;
- „Kamera nélkül is használható”.

A user decision ne legyen dark patternnel kikényszerítve.

---

# 13. Setup és kalibráció

## 13.1 Setup célok

A setup wizard mérje és mutassa:

- a gitár nyakának láthatóságát;
- a pengető kéz láthatóságát;
- a fogólap kéz láthatóságát;
- felsőtest láthatóságát posture módhoz;
- fényerőt;
- blur-t;
- occlusiont;
- kamera távolságot proxy metrikával;
- szükséges orientationt;
- foreground/background szeparációt.

## 13.2 Setup profilok

```text
leftHandFocus
rightHandFocus
fullUpperBody
practiceBalanced
songPerformance
experimentalFretboard
```

Egyetlen kameraállás nem optimalizálható minden célra. A UI ezt mondja ki.

## 13.3 Manual guitar anchor calibration

A megbízható MVP tartalmazzon manual anchor flow-t:

1. a felhasználó megjelöli a nut közelét;
2. megjelöli a bridge vagy sound-hole/pickup zónát;
3. a rendszer kirajzolja a nyak centerline-t;
4. a felhasználó finomíthatja a neck polygon széleit;
5. a rendszer quality score-t ad;
6. a kalibráció menthető camera/profile kombinációhoz.

A manual calibration nem kudarc. Production fallback és ground-truth eszköz.

## 13.4 Calibration validity

A kalibráció érvénytelenedik, ha:

- camera device megváltozik;
- orientation megváltozik;
- zoom jelentősen változik;
- gitárgeometria elmozdul a tolerancián túl;
- session közben tracking confidence tartósan alacsony;
- felhasználó új hangszert választ;
- app verzió vagy schema breaking változás történik.

---

# 14. Frame quality assessor

## 14.1 Metrikák

Kötelező MVP metrikák:

- mean luminance;
- highlight clipping arány;
- shadow clipping arány;
- blur score;
- frame-to-frame camera motion;
- hand visibility;
- pose visibility;
- guitar ROI coverage;
- occlusion ratio;
- inference freshness;
- dropped frame rate.

## 14.2 Quality state

```dart
final class VisionFrameQuality {
  const VisionFrameQuality({
    required this.lighting,
    required this.blur,
    required this.framing,
    required this.occlusion,
    required this.stability,
    required this.overall,
  });
}
```

## 14.3 Quality feedback prioritás

A setup feedback ne adjon egyszerre öt problémát. Prioritási sorrend:

1. kameraengedély;
2. nincs gitár vagy kéz a frame-ben;
3. túl sötét vagy kiégett kép;
4. jelentős blur;
5. rossz framing;
6. instabil kamera;
7. alacsony modellconfidence.

---

# 15. Hand landmark pipeline

## 15.1 Provider contract

```dart
abstract interface class HandLandmarkProvider {
  String get modelId;
  String get modelVersion;
  Future<AppResult<void>> initialize(HandModelConfig config);
  Future<AppResult<HandLandmarkResult>> infer(VisionImage image);
  Future<void> close();
}
```

A domain nem feltételez fix landmark indexeket. Az adapter mapolja a provider outputját stabil StrumSight landmark ID-kre.

## 15.2 Running mode

Realtime sessionben video/live-stream mód szükséges, timestampelt inputtal. Az input timestamp nem csökkenhet.

## 15.3 Kézszerep hozzárendelés

A modell handedness osztálya és a gitáros szerep külön fogalom:

```text
physicalLeftHand / physicalRightHand
frettingHand / pickingHand
```

A mapping függ:

- left-handed mode-tól;
- kamera mirroringtól;
- gitár orientationtől;
- setup profiltól.

## 15.4 Tracking és smoothing

Kötelező:

- track ID stabilizálás;
- confidence-aware exponential smoothing vagy One Euro filter;
- teleport/jump rejection;
- maximum gap interpolation csak rövid időre;
- hosszabb hiány esetén track termination;
- raw és smoothed coordinate külön kezelése;
- latency mérés.

Smoothing nem rejtheti el a gyors strum mozgást. Jobb kézhez és statikus posture-höz külön paraméterprofil szükséges.

---

# 16. Pose landmark pipeline

## 16.1 Cél

A pose pipeline csak olyan pontokat használjon, amelyek a gitártartás és felsőtest feedback szempontjából szükségesek:

- vállak;
- könyökök;
- csuklók;
- csípő referencia, ha látható;
- fej/fül csak opcionális neck posture proxyhoz.

## 16.2 Privacy minimization

Arc- és arckifejezés-elemzés nem része a rendszernek. Ha a pose provider arcpontokat ad, azok ne kerüljenek persistence-be, insightba vagy logba.

## 16.3 Pose cadence

A posture lassabb jelenség, ezért a pose model alacsonyabb frekvencián futhat, mint a hand model. Device tier alapján külön cadence legyen.

## 16.4 Posture baseline

A feedback lehet relatív a session eleji baseline-hoz. Ez csökkenti az eltérő testalkat és kameraperspektíva miatti hamis abszolút ítéletet.

---

# 17. Gitár- és fogólapgeometria

## 17.1 MVP: manual + tracked geometry

A production MVP nem függhet kizárólag automatikus guitar detector modelltől. A manual calibration után a rendszer frame-to-frame trackinggel frissíti a geometriát.

## 17.2 Koordinátarendszer

Definiálj normalizált gitárkoordinátát:

```text
u = nut → bridge irány, 0..1
v = bass edge → treble edge irány, 0..1
z = képsíkra merőleges relatív mélység, ha becsülhető
```

Ez alapján számítható:

- kéz távolsága a nyaktól;
- mozgás a nyak mentén;
- picking zone;
- stroke pálya a húrokra merőleges irányban;
- relatív wrist angle.

## 17.3 Homography

A nyak négyszögéből számított projektív transzformáció pure Dart modul legyen. Degenerált vagy instabil pontok esetén ne adjon érvényes mappinget.

## 17.4 Fret becslés

A fret pozíciók fizikai eloszlása nem lineáris. Exact fret mapping csak akkor készülhet, ha:

- nut és legalább egy további referencia megbízható;
- nyak perspektívája valid;
- hangszer scale/fret count beállítás ismert vagy becsült;
- a finger tip és contact zóna látható;
- confidence eléri az experimental küszöböt.

Az MVP insightokhoz fret index nem szükséges.

---

# 18. Koordináta- és időnormalizálás

## 18.1 Koordinátaterek

A rendszer explicit különítse el:

```text
sensor coordinates
buffer coordinates
upright image coordinates
preview coordinates
normalized frame coordinates
guitar coordinates
screen overlay coordinates
```

Minden transzformáció legyen invertálható, amikor matematikailag lehetséges.

## 18.2 Front camera mirroring

A preview lehet tükrözött, de a modell input és domain koordináta ne legyen implicit módon tükrözve. A `mirrored` metadata kötelező.

## 18.3 Property tesztek

Kötelező invariánsok:

- rotate 90° négyszer = eredeti;
- mirror kétszer = eredeti;
- frame → preview → frame round-trip tolerancián belül;
- homography inverse round-trip;
- crop transform nem hoz 0..1 tartományon kívüli érvényes pontot clamp nélkül;
- invalid polygon explicit failure.

---

# 19. Bal kéz technikai metrikák

## 19.1 Production MVP metrikák

### Wrist deviation proxy

A csukló, kézközép és alkarpontokból számított relatív szög. Nem egészségügyi mérés.

### Hand-to-neck distance

A kézcentrum vagy kiválasztott MCP pontok távolsága a neck plane/centerline relatív koordinátájában.

### Chord-change travel

Két stabil kézpozíció közötti normalizált pályahossz.

### Ready-position time

Az audio target esemény előtt mennyi idővel kerül a kéz a következő stabil zónába. Csak olyan gyakorlatnál használható, ahol ismert a következő cél.

### Position stability

A kéz jittere sustain vagy tartott akkord alatt.

### Finger spread proxy

Landmark alapú ujjterpesz, csak megfelelő visibility mellett.

## 19.2 Nem engedélyezett MVP claim

A rendszer nem mondhatja production módban:

- „A mutatóujjad a 2. húron rossz helyen van.”
- „Túl messze vagy a bundtól.”
- „Ez az ujj lefogja a szomszéd húrt.”

Ezekhez fine-grained contact capability szükséges.

## 19.3 Feedback policy példa

```text
IF wrist_metric.confidence >= 0.80
AND visible_duration >= 4.0 s
AND absolute_deviation > calibrated_threshold
AND quality.overall >= good
THEN emit LEFT_WRIST_DEVIATION_SUSTAINED
ELSE do not emit negative insight
```

---

# 20. Jobb kéz technikai metrikák

## 20.1 Stroke trajectory

Az audio strum onset körüli időablakban a picking hand vagy index/thumb proxy mozgáspályája.

Metrikák:

- irány;
- amplitúdó;
- sebesség;
- path linearity;
- beat-to-beat consistency;
- turnaround smoothness;
- down/up asymmetry.

## 20.2 Picking zone

A picking hand pozíciója a bridge–neck irány mentén. A rendszer csak relatív zónát adjon:

```text
nearBridge
middleBody
nearNeck
outsideCalibratedZone
```

Hangminőségi ítéletet ne adjon önmagában a zóna alapján.

## 20.3 Motion economy

A stroke eseményhez szükséges és a két esemény közötti fölösleges pályahossz elkülönítése. Ez csak több ismétlésből, nem egyetlen stroke-ból számítható.

## 20.4 Wrist vs arm contribution

A wrist, elbow és hand mozgás relatív aránya lehet observation. Ne legyen univerzális „helyes/rossz” szabály, mert stílus- és feladatfüggő.

## 20.5 Pick grip és palm mute

Kísérleti. Csak külön dataset és megfelelő kameraállás esetén.

---

# 21. Testtartás és ergonómiai insightok

## 21.1 Támogatott megfigyelések

- vállmagasság relatív különbsége;
- vállszög változása a session során;
- törzs oldalirányú dőlése;
- könyök pozíciójának tartós driftje;
- fej/nyak relatív előretolódás proxy, ha látható;
- gitártest és felsőtest relatív stabilitása;
- gyakori nagy korrekciós mozgás.

## 21.2 Baseline-alapú értékelés

Az első stabil 10–20 másodperc lehet személyes baseline, feltéve, hogy a setup quality jó. A rendszer inkább a session alatti változást jelezze, mint abszolút testtartási normát.

## 21.3 Safety nyelvezet

Megengedett:

- „A jobb vállad magasabban maradt az utolsó két percben.”
- „Próbálj rövid szünetet tartani és lazán újra beállni.”

Nem megengedett:

- „Rosszul tartod magad.”
- „Ez sérülést okoz.”
- „Íngyulladásod van.”

Fájdalom említésekor a rendszer általános, óvatos tanácsot adjon és ne diagnosztizáljon.

---

# 22. Audio–vision szinkron

## 22.1 Követelmény

A kamera és az audio külön pipeline, külön latencyvel. A rendszer közös monotonic session time-ra mapolja:

- audio engine time;
- camera capture timestamp;
- inference completion timestamp;
- UI render timestamp.

## 22.2 Clock mapping

```dart
final class ClockMapping {
  const ClockMapping({
    required this.source,
    required this.target,
    required this.offsetUs,
    required this.driftPpm,
    required this.confidence,
  });
}
```

A mappinget session elején és hosszabb session közben újra lehet becsülni.

## 22.3 Calibration event

A felhasználó végezhet egyszerű vizuális-audio kalibrációt:

- egyértelmű pengetés vagy taps;
- audio onset;
- kézsebesség-csúcs;
- offset becslés több ismétlésből;
- outlier rejection.

## 22.4 Sync quality

```text
excellent   <= validated tight threshold
good        <= production feedback threshold
degraded    insight only, no event-level verdict
unavailable aggregate metrics only
```

A konkrét milliszekundumküszöböket valós eszközös benchmark után kell rögzíteni, nem előre kitalálni.

---

# 23. Observation fusion és feedback policy

## 23.1 Fusion input

- smoothed hand tracks;
- pose tracks;
- guitar geometry;
- frame quality;
- audio strum events;
- expected Practice/Song events;
- user handedness;
- exercise context;
- calibration profile;
- device tier.

## 23.2 Ablakos aggregáció

Feedback ne egyetlen frame alapján készüljön. Metrikánként definiálni kell:

- minimum observation count;
- minimum visible duration;
- maximum gap;
- outlier policy;
- aggregation mód;
- confidence formula;
- cooldown;
- session minimum ismétlés.

## 23.3 Feedback budget

Realtime sessionben:

- egy időben legfeljebb egy aktív technikai cue;
- cue minimum megjelenési idő;
- ugyanaz a cue cooldown alatt nem ismétlődik;
- setup cue elsőbbséget élvez a technikai cue előtt;
- veszélyes vagy leértékelő nyelvezet tilos;
- pozitív megerősítés csak valódi javulás vagy stabil teljesítés esetén.

## 23.4 Insight prioritás

Javasolt sorrend:

1. nem megfigyelhető / setup;
2. audio–vision sync probléma;
3. stabil, nagy hatású technikai minta;
4. session végére romló forma;
5. kisebb konzisztenciaprobléma;
6. kísérleti megfigyelés.

---

# 24. Vision Practice UX

## 24.1 Képernyőszerkezet

```text
┌──────────────────────────────────────┐
│ Camera preview + safe-area overlay   │
│ hand / guitar / pose quality chips   │
│ active cue                           │
├──────────────────────────────────────┤
│ Exercise target / metronome / score  │
├──────────────────────────────────────┤
│ Pause  |  Recalibrate  |  Stop       │
└──────────────────────────────────────┘
```

## 24.2 Overlay szabályok

- skeletal overlay alapértelmezetten visszafogott;
- ne takarja a kéz kritikus részét;
- külön kapcsolható debug landmark mód;
- confidence színkód mellett mindig legyen szöveg vagy ikon;
- tükörnézet konzisztens legyen a felhasználói mozgással;
- orientation változás kontrollált session restartot vagy recalibrationt kérjen.

## 24.3 Feedback módok

```text
silentCapture        — csak session végi összefoglaló
minimalCue           — egy rövid vizuális cue
coachCue             — vizuális + opcionális haptic
accessibilityAudio   — rövid hangjelzés, nem TTS folyamatosan
labOverlay           — részletes landmark és metric debug
```

## 24.4 Kéz nélküli vezérlés

A gitáros keze foglalt. Alapműveletek nagy gombokkal, count-in idővel és opcionális voice command integrációs ponttal készüljenek, de folyamatos speech recognition nem része ennek az Epicnek.

---

# 25. Practice Engine integráció

## 25.1 VisionPracticeContract

```dart
final class VisionPracticeContract {
  const VisionPracticeContract({
    required this.requiredCapabilities,
    required this.setupProfile,
    required this.metricIds,
    required this.feedbackMode,
    required this.scoringPolicy,
  });
}
```

## 25.2 Vision score külön dimenzió

A `PracticeSessionResult` bővítése opcionális vision summaryval:

```dart
final VisionSessionResult? vision;
```

Nem kötelező közös százalékos score. Az első release-ben:

- audio accuracy;
- rhythm;
- chord;
- vision technique;
- observation quality

külön dimenzióként jelenjen meg.

## 25.3 Vision-aware Speed Builder

A tempo csak akkor emelkedjen automatikusan, ha:

- audio scoring megfelel;
- vision quality jó;
- kiválasztott technique stability nem romlik a policy küszöb fölé;
- nincs calibration loss.

Ha a vision nem elérhető, a régi audio-only Speed Builder működjön.

## 25.4 Gyakorlatpéldák

- Small Strum Motion;
- Down/Up Symmetry;
- Relaxed Wrist Baseline;
- Chord Change Economy;
- Shoulder Reset Warm-up;
- Picking Zone Consistency;
- Slow Clean Transition;
- Camera Setup Drill.

Minden gyakorlat tartalmazzon:

- célmérőszámot;
- minimum capabilityt;
- setup profilt;
- fallbacket;
- safety note-ot;
- session végi összefoglaló policyt.

---

# 26. Song Trainer integráció

## 26.1 Section-level tracking

Az A–B loophoz vision aggregate kapcsolható:

- stroke amplitude consistency;
- hand travel;
- posture drift;
- ready-position timing;
- observation quality.

## 26.2 Performance terhelés

Backing audio + metronóm + audio scoring + camera preview + inference együtt csak benchmarkolt device tieren engedélyezhető.

Low tier fallback:

- 10–15 FPS hand tracking;
- pose ritkítva;
- overlay 10 FPS;
- session végi summary;
- nincs kísérleti guitar detector.

## 26.3 Result link

A Song Trainer result és Vision result közös:

- session ID;
- song ID;
- section ID;
- timeline origin;
- loop iteration ID.

---

# 27. AI Tutor és Analysis integráció

## 27.1 Tutor adapter

A Tutor Context Assembler csak a következőket kapja:

- VisionSession summary;
- top insightok;
- evidence ID-k;
- confidence;
- observability;
- setup quality;
- capability verziók.

Nem kap:

- frame pixelt;
- arc landmarkot;
- raw landmark idősor teljes tömegét;
- kamera device serialt;
- háttérképet.

## 27.2 Tutor claim guard

A tutor prompt előtti validator blokkolja az olyan claimet, amely nem támogatott vision evidence-szel.

## 27.3 Analysis adapter

Az AnalysisDocument opcionális `visionReference` mezőt kapjon, ne embedelje teljesen a VisionSessionResultot, ha az külön repositoryban van.

## 27.4 Cross-modal insight

Példa:

- audio szerint timing romlik;
- vision szerint stroke amplitude növekszik;
- sync quality jó;
- insight: „A nagyobb kézmozgás együtt jelent meg a késésekkel.”

Ez inferred claim. Külön provenance és magasabb confidence gate szükséges.

---

# 28. Persistence és adatvédelem

## 28.1 Menthető adatok

Alapértelmezetten menthető:

- session metadata;
- model version;
- capability report;
- quality summary;
- aggregate metric;
- insight;
- kalibrációs pontok normalizált koordinátában;
- performance telemetry lokálisan.

Nem menthető alapértelmezetten:

- raw frame;
- preview screenshot;
- videó;
- teljes landmark frame stream;
- arc landmark;
- background image.

## 28.2 Landmark retention

Részletes landmark idősor csak külön debug/Lab opcióval, rövid retentionnel és egyértelmű törléssel menthető. Production consumer flowban aggregate elég.

## 28.3 Export

Felhasználói export gépi olvasható JSON lehet, raw image nélkül. Tartalmazza:

- schema version;
- model version;
- metric summary;
- insight;
- calibration profile metadata.

## 28.4 Törlés

A user törölhesse:

- egy session vision adatait;
- összes vision historyt;
- camera calibration profile-t;
- Lab capture-t;
- experimental model feedback historyt.

---

# 29. Teljesítmény, device tier és thermal policy

## 29.1 Mérendő adatok

- camera initialization time;
- preview first-frame time;
- frame capture FPS;
- inference FPS;
- end-to-end observation latency;
- dropped frame ratio;
- memory peak;
- sustained memory;
- CPU;
- GPU/NPU usage, ha elérhető;
- battery drain;
- thermal state;
- audio DSP latency változása;
- UI jank.

## 29.2 Device tier

```text
unsupported
basic
standard
highPerformance
```

A tier runtime benchmarkból és statikus capabilityből képződjön. A modell vagy feature ne csak márkanév alapján döntsön.

## 29.3 Audio prioritás

Ha Vision miatt az audio DSP határidő sérül:

1. Vision FPS csökken;
2. pose leáll;
3. overlay ritkul;
4. vision inference leáll;
5. audio folytatódik.

A Computer Vision soha nem ronthatja csendben a StrumSight alap audiofelismerését.

## 29.4 Thermal degradation

Tartós melegedésnél:

- UI jelzi a quality csökkenést;
- a session folytatható audio-only módban;
- ne legyen automatikus negatív feedback a degraded szakaszból;
- performance summary rögzítse a degradációt.

---

# 30. Modellkezelés és manifest

## 30.1 Manifest

Minden vision modellhez:

```json
{
  "modelId": "hand_landmarker",
  "version": "1.0.0",
  "sha256": "...",
  "input": {
    "width": 256,
    "height": 256,
    "format": "RGB"
  },
  "outputSchema": "strumsight.hand_landmarks.v1",
  "license": "documented",
  "minimumDeviceTier": "basic",
  "evaluationReport": "docs/eval/vision/..."
}
```

## 30.2 Model adapter

Az adapter ellenőrizze:

- checksum;
- input shape;
- output count;
- output range;
- model schema compatibility;
- initialization timeout;
- acceleration backend fallback.

## 30.3 Update policy

Model update csak akkor merge-elhető, ha:

- manifest frissült;
- model card frissült;
- evaluation report frissült;
- golden fixture parity dokumentált;
- latency benchmark nem romlott indokolatlanul;
- false feedback gate zöld;
- rollback asset elérhető.

---

# 31. Dataset és annotáció

## 31.1 Dataset kategóriák

- synthetic geometry fixtures;
- consentelt belső fejlesztői videók;
- különböző gitártípusok;
- bal- és jobbkezes játék;
- eltérő bőrtónusok és ruházat;
- különböző fények;
- front és rear camera;
- ülő és álló testtartás;
- akusztikus és elektromos gitár;
- különböző nyakszínek és háttérkontraszt;
- occlusion és blur edge case-ek;
- helyes és szándékosan változtatott technikai mozgások.

## 31.2 Consent

Minden emberi felvételhez:

- explicit consent;
- felhasználási cél;
- retention;
- hozzáférési kontroll;
- törlési folyamat;
- publikálási tiltás, ha nincs külön engedély;
- annotátor privacy guideline.

## 31.3 Annotációs schema

Lehetséges label:

- frame timestamp;
- visible hands;
- hand role;
- key landmarks;
- guitar neck polygon;
- nut/bridge anchor;
- pose points;
- quality flags;
- strum event;
- technique window;
- observability;
- annotator confidence.

## 31.4 Ground truth korlát

Szubjektív „jó technika” címke helyett elsőként objektívebb mennyiségeket kell annotálni:

- landmark;
- pálya;
- szög;
- távolság;
- időpont;
- visibility;
- setup quality.

A pedagógiai feedbacket külön expert policy és user study validálja.

---

# 32. Evaluation stratégia

## 32.1 Modellmetrikák

- hand detection recall;
- landmark error normalizált skálán;
- track continuity;
- handedness accuracy;
- pose landmark visibility;
- guitar ROI IoU, ha automatic detector van;
- calibration drift;
- inference latency;
- memory;
- dropped frame rate.

## 32.2 Termékmetrikák

- setup completion rate;
- calibration success;
- time-to-ready;
- false negative setup warning;
- false technical feedback rate;
- no-feedback rate;
- user correction acceptance;
- session completion;
- audio-only fallback success;
- battery/thermal stop rate.

## 32.3 False feedback gate

A production rollout legfontosabb gate-je nem a landmark demo látványossága, hanem a hamis technikai feedback aránya.

Kötelező kézi review:

- legalább több eszköz és camera orientation;
- bal- és jobbkezes session;
- több fényhelyzet;
- több gitár;
- setup hibák;
- occlusion;
- gyors strum;
- lassú chord change;
- posture drift.

## 32.4 Confidence calibration

A 0.8 confidence jelentése legyen mérhető. Reliability diagram vagy bucketelt calibration report szükséges minden olyan metrikához, amely negatív feedbacket ad.

## 32.5 Parity és fairness

A quality és tracking teljesítményt csoportok és körülmények szerint külön kell vizsgálni. Ha egy körülményben jelentősen rosszabb, a capability legyen degraded, ne adjon magabiztos feedbacket.

---

# 33. Accessibility és lokalizáció

## 33.1 Nem csak szín

Quality és confidence ne csak zöld/sárga/piros színnel jelenjen meg. Ikon és rövid szöveg szükséges.

## 33.2 Screen reader

A kamera preview dekoratív elemként kezelhető, de az aktuális setup instruction és active cue accessibility live region legyen, kontrollált frissítési gyakorisággal.

## 33.3 Mozgáscsökkentés

A skeleton és pulse animációk csökkentett motion setting mellett minimalizálódjanak.

## 33.4 Fizikai elhelyezés

A setup instrukció ne feltételezze, hogy minden felhasználó állványt használ. Ajánljon stabil asztali és polcos alternatívát is, de ne ígérjen azonos qualityt.

## 33.5 Lokalizáció

Minden insight és setup code angol és magyar ARB-be kerüljön. A technikai kifejezések legyenek következetesek:

- fretting hand — fogólapkéz / lefogó kéz;
- picking hand — pengető kéz;
- wrist deviation — csukló eltérése;
- framing — képkivágás;
- tracking lost — követés megszakadt.

---

# 34. Biztonság és abuse prevention

## 34.1 Kameraindítás

A kamera csak explicit user action után indulhat. Deep link vagy background task nem indíthatja automatikusan.

## 34.2 Screenshot és debug capture

- consumer buildben tiltott automatikus screenshot;
- Lab buildben külön watermark és consent;
- debug capture ne tartalmazzon auth tokent vagy személyes overlay szöveget;
- fájl path traversal ellen védett;
- retention limitált.

## 34.3 Model input

A modell parser védje:

- invalid buffer size;
- unsupported pixel format;
- overflow;
- corrupt asset;
- output NaN/Infinity;
- váratlan output shape.

## 34.4 Logging

Tilos logolni:

- raw pixel adatot;
- base64 képet;
- teljes landmark idősorokat production logban;
- camera preview screenshotot;
- személyazonosító képleírást.

Megengedett aggregate:

- FPS;
- latency;
- quality bucket;
- capability state;
- model version;
- failure code.

---

# 35. Tesztelési stratégia

## 35.1 Unit tesztek

- koordinátatranszformációk;
- homography;
- smoothing;
- track assignment;
- capability state;
- state machine;
- feedback policy;
- quality aggregation;
- audio–vision mapping;
- persistence migration;
- model manifest validation.

## 35.2 Golden fixture tesztek

Tárolt, anonimizált model outputból:

- hand landmark mapping;
- pose mapping;
- geometry mapping;
- overlay coordinate;
- insight selection.

A CI-nek nem kell minden esetben valódi kamerát vagy natív inference-et futtatnia.

## 35.3 Native/platform tesztek

Android instrumented:

- permission;
- camera open/close;
- lifecycle pause/resume;
- frame callback;
- rotation;
- front camera mirror;
- analyzer backpressure;
- resource release.

iOS későbbi parity:

- permission;
- interruption;
- sample buffer queue;
- orientation;
- background stop.

## 35.4 Widget tesztek

- setup wizard;
- permission denied;
- quality cue;
- calibration editor;
- active insight;
- degraded mode;
- session summary;
- delete confirmation;
- camera unavailable fallback.

## 35.5 Integration tesztek

- Practice + Vision;
- Song loop + Vision;
- route leave resource release;
- app background;
- audio-only fallback;
- thermal simulation;
- model init failure;
- storage migration;
- tutor evidence assembly.

## 35.6 Valós eszközös tesztmátrix

Legalább:

- több Android gyártó;
- low/mid/high tier;
- front és rear camera;
- portrait és landscape;
- eltérő fény;
- bal- és jobbkezes;
- akusztikus és elektromos;
- gyors és lassú mozgás;
- hosszabb session;
- háttérbe küldés;
- hívás vagy kamera interruption, ahol reprodukálható.

---

# 36. Feature flagek és rollout

## 36.1 Javasolt flagek

```text
visionEnabled
visionSetupEnabled
visionHandTrackingEnabled
visionPoseTrackingEnabled
visionGuitarGeometryEnabled
visionPracticeIntegrationEnabled
visionSongIntegrationEnabled
visionTutorIntegrationEnabled
visionAnalysisIntegrationEnabled
visionExperimentalFineFretEnabled
visionLabCaptureEnabled
```

## 36.2 Rollout szintek

```text
0 — compiled out / unavailable
1 — internal setup and quality only
2 — internal hand/pose overlay
3 — shadow observations, no user feedback
4 — opt-in beta session summary
5 — limited realtime cues
6 — production supported metrics
7 — experimental fine-grained features, explicit opt-in
```

## 36.3 Shadow mode

Shadow mode-ban:

- observation és metric készül;
- user nem kap negatív feedbacket;
- performance és confidence mérhető;
- Lab review lehetséges explicit consentelt fixture-rel;
- audio scoring változatlan.

## 36.4 Rollback

Bármely model vagy policy külön visszakapcsolható legyen az alkalmazás többi részének új release-e nélkül, amennyiben a konfigurációs rendszer ezt biztonságosan támogatja. Offline buildben legalább lokális feature flag és előző asset rollback szükséges.

---

# 37. Codex végrehajtási szabályok

Minden kör elején a Codex:

1. olvassa el az `AGENTS.md` fájlt;
2. olvassa el a Chapter 2, 3, 5 és ezt a fejezetet;
3. ellenőrizze a jelenlegi `HANDOFF.md` állapotot;
4. keresse meg az érintett audio, lifecycle, permission és routing teszteket;
5. csak az aktuális kör feladatait végezze el;
6. ne indítson másik körbe tartozó model traininget;
7. ne adjon production feedbacket teszt nélküli metrikából;
8. ne mentsen raw frame-et consumer kódban;
9. ne küldjön kameraképet backendnek;
10. ne módosítsa a DSP-paramétereket a vision fejlesztés miatt;
11. ne tegyen platform-specifikus típust a domainbe;
12. minden camera resource-hoz írjon dispose/lifecycle tesztet;
13. minden új metrikához definiáljon observability és confidence gate-et;
14. minden model assethez frissítse a manifestet;
15. a kör végén külön jelentse a valós eszközön nem ellenőrzött pontokat;
16. ne állítsa sikeresnek a camera tesztet, ha csak fake adapteren futott;
17. frissítse a `HANDOFF.md` fájlt;
18. a következő körbe ne kezdjen bele.

Kötelező körvégi jelentés:

```text
Modified files
Implemented scope
Architecture decisions
Commands run
Unit/widget/native test results
Real-device verification
Performance measurements
Known limitations
Deferred work
Exact next round
```

---

# 38. Fejlesztési körök


# Kör 1 — Vision baseline, capability audit és ADR-ek

## Cél

A jelenlegi repository kamera- és platformképességeinek pontos felmérése, mérhető kiindulási állapot és kötelező vision architekturális döntések létrehozása.

## Feladatok

- Készíts `docs/baseline/vision-epic-start.md` fájlt a Flutter, Android, iOS, permission, lifecycle és device target állapottal.
- Listázd a jelenlegi audio session ownership, app lifecycle és route dispose mintákat, amelyekhez a camera lifecycle-nak igazodnia kell.
- Rögzítsd, hogy a repositoryban nincs camera dependency, camera permission és vision model asset.
- Hozd létre az ADR-eket: privacy-by-default, capability-aware feedback, Android-first camera strategy, manual calibration fallback, audio-priority degradation, no-raw-frame persistence.
- Definiáld a támogatott és kísérleti metric listát. Minden metrichez adj observability előfeltételt.
- Készíts device test matrix sablont és performance benchmark sablont.
- Ne módosíts production kódot ebben a körben.

## Kötelező ellenőrzések

- `flutter analyze lib/ test/`
- `flutter test`
- `cd backend && python -m pytest -q`
- A baselineban jelöld külön a le nem futott iOS és valós kamera teszteket.

## Elfogadási feltételek

- Létrejött legalább hat vision ADR.
- Dokumentált a kamera nélküli jelenlegi állapot.
- A production és experimental scope egyértelmű.
- Alkalmazáskód és DSP nem változott.
- A meglévő tesztek zöldek.

## Javasolt commit

```text
docs(vision): establish computer vision baseline and ADRs
```


# Kör 2 — Camera technology spike és döntési kapu

## Cél

Mérési alapon eldönteni, hogy a hivatalos Flutter camera réteg elegendő-e, vagy vékony saját platform adapter szükséges.

## Feladatok

- Készíts külön spike branchet vagy izolált prototype-ot, amely previewt és frame streamet indít Androidon.
- Mérd az init időt, frame FPS-t, pixel formatot, rotation metadata minőségét, buffer copy számát és close időt.
- Ellenőrizd a front camera mirroringot, portrait/landscape váltást és app pause/resume viselkedést.
- Mérd legalább két Android eszközön vagy egy valós és egy emulátoros környezetben, az emulátor korlátait dokumentálva.
- Vizsgáld meg, hogy a frame capture timestamp alkalmas-e monotonic audio–vision mappingre.
- Készíts ADR-t: plugin használat, CameraX-backed implementation vagy saját platform channel.
- A spike kódot ne merge-eld productionbe, amíg nincs contract és teszt.

## Kötelező ellenőrzések

- Debug APK build.
- Valós device preview start/stop legalább 20 alkalommal.
- App background/foreground teszt.
- Memory snapshot start előtt, futás közben és close után.

## Elfogadási feltételek

- A camera technológiai döntés mérési adatokon alapul.
- Dokumentáltak a platformkorlátok.
- Ismert a frame format és timestamp stratégia.
- Nincs el nem engedett camera resource a spike tesztben.

## Javasolt commit

```text
spike(vision): evaluate mobile camera capture strategy
```


# Kör 3 — Core camera contract és fake infrastruktúra

## Cél

Platformfüggetlen, teljesen tesztelhető camera capture és session contract létrehozása production plugin bekötése nélkül.

## Feladatok

- Hozd létre a `core/camera` domain contractokat: device, request, frame metadata, session event, handle és failure mapping.
- Definiáld a támogatott pixel formatokat és orientation enumokat.
- A `CameraFrame` használjon explicit ownership modellt; dokumentáld, mikor érvénytelen a buffer.
- Hozz létre fake camera capture-t determinisztikus timestampelt frame streammel.
- Implementálj controllable fake hibákat: busy, unavailable, initialization failure, frame failure, interruption.
- Írj unit tesztet close idempotenciára és close utáni callback elutasítására.
- Ne tegyél raw frame-et Riverpod state-be.

## Kötelező ellenőrzések

- `dart format --output=none --set-exit-if-changed lib test`
- `flutter analyze lib/ test/`
- `flutter test test/core/camera`

## Elfogadási feltételek

- A contract nem importál konkrét camera plugint.
- A fake adapterrel minden lifecycle állapot reprodukálható.
- A frame ownership dokumentált és tesztelt.
- Close többször biztonságos.

## Javasolt commit

```text
feat(camera): add platform-neutral capture contracts
```


# Kör 4 — Camera permission és platform deklarációk

## Cél

A kameraengedély biztonságos, opcionális és lokalizált bevezetése Androidon és iOS-en.

## Feladatok

- Add hozzá az Android `CAMERA` permissiont a main manifesthez.
- Add hozzá az iOS `NSCameraUsageDescription` kulcsot angol, privacy-pontos szöveggel.
- Bővítsd a permission gatewayt camera state-tel.
- Készíts permission screen/panel flow-t denied, permanently denied, restricted és unavailable állapotokra.
- A kameraengedély elutasítása ne okozzon app startup hibát.
- A Vision feature route vagy entry point csak explicit user action után kérjen permissiont.
- Adj angol és magyar lokalizációt minden állapothoz.
- Írj widget tesztet arra, hogy camera nélkül az audio-only CTA elérhető.

## Kötelező ellenőrzések

- `flutter analyze lib/ test/`
- `flutter test test/features/vision test/core/platform`
- Android manifest merge ellenőrzés.
- iOS plist strukturális ellenőrzés.

## Elfogadási feltételek

- Permission csak Vision flow-ban kérődik.
- Permanently denied esetben Settings CTA jelenik meg.
- Camera nélkül minden meglévő feature elérhető.
- A platform usage szöveg nem állít felhőfeltöltést.

## Javasolt commit

```text
feat(vision): add optional camera permission flow
```


# Kör 5 — CameraSessionCoordinator és lifecycle ownership

## Cél

Biztosítani, hogy egyszerre pontosan egy StrumSight modul használja a kamerát, és minden kilépési útvonal felszabadítsa.

## Feladatok

- Hozd létre a `CameraSessionCoordinator` és lease modellt.
- Definiáld az owner típusokat: visionSetup, visionPractice, songVision, labCapture.
- Második owner esetén kontrollált `CameraBusyFailure` legyen.
- Integráld az app lifecycle pause/hidden/detached eseményeit.
- Route leave esetén close legyen kötelező és tesztelt.
- Start/close, close/close, start közbeni cancellation és interruption versenyhelyzeteket védd.
- A kamera ne induljon automatikusan resume után a felhasználó explicit folytatása nélkül.
- Adj strukturált resource lifecycle log eventeket raw adatok nélkül.

## Kötelező ellenőrzések

- `flutter test test/core/camera/camera_session_coordinator_test.dart`
- Widget route-leave teszt fake camera adapterrel.
- Valós Android camera indicator ellenőrzés.

## Elfogadási feltételek

- Egyszerre egy camera lease lehetséges.
- App háttérben nincs aktív kamera.
- Route leave után megszűnik a stream.
- Nincs state update dispose után.
- Minden race teszt zöld.

## Javasolt commit

```text
fix(camera): enforce exclusive lifecycle-safe ownership
```


# Kör 6 — Android camera production adapter

## Cél

A kiválasztott capture stratégiával stabil Android preview és latest-frame analysis stream implementálása.

## Feladatok

- Implementáld a production Android adaptert a Kör 2 ADR-je szerint.
- A frame pipeline latest-frame backpressure-t használjon.
- Őrizd meg a capture timestampet, rotationt, mirror state-et, width/heightet és cropot.
- Minimalizáld a pixel buffer másolást; dokumentáld az elkerülhetetlen copykat.
- A frame callback mindig engedje el a platform buffert, hiba esetén is.
- Kezeld camera disconnected, in-use, max-cameras-in-use és device error eseményeket stabil failure code-dal.
- Preview és analysis lifecycle ugyanahhoz a session lease-hez tartozzon.
- Ne implementálj még ML inference-et.

## Kötelező ellenőrzések

- Android instrumented open/close teszt.
- 100 start/stop ciklus stresszteszt legalább egy valós eszközön.
- Rotation és mirror fixture.
- Dropped frame telemetry ellenőrzés.
- `flutter build apk --debug`

## Elfogadási feltételek

- Stabil preview és frame stream működik.
- Nincs korlátlan frame queue.
- Platform buffer mindig felszabadul.
- Hibák AppFailure-re mapolódnak.
- A microphone-only tesztek nem regresszálnak.

## Javasolt commit

```text
feat(camera): implement Android capture adapter
```


# Kör 7 — Frame transform és overlay koordinátarendszer

## Cél

Minden orientation, crop és mirror esetben helyes, pure Dart koordinátatranszformáció létrehozása.

## Feladatok

- Implementáld a sensor, upright, normalized, preview és overlay koordinátatereket.
- Készíts composable transform típust és inverse-t.
- Kezeld a front preview mirror és model input nem tükrözött esetét.
- Implementálj aspect-fit és aspect-fill preview mappinget.
- Adj safe-area és letterbox offset kezelést.
- Készíts grid fixture képeket vagy numerikus fixture pontokat minden 0/90/180/270 fokra.
- Írj property teszteket round-trip és mirror invariánsokra.
- A presentation csak ezt a mappinget használhatja overlayhez.

## Kötelező ellenőrzések

- `flutter test test/core/camera/camera_transform_test.dart`
- `flutter test test/property/camera_transform_property_test.dart`
- Golden overlay teszt portrait és landscape módban.

## Elfogadási feltételek

- A transzformáció platformfüggetlen.
- Front camera overlay nem fordul rossz oldalra.
- Round-trip hiba a dokumentált tolerancián belül.
- Nincs ad hoc coordinate math widgetekben.

## Javasolt commit

```text
feat(vision): normalize camera and overlay coordinates
```


# Kör 8 — Vision setup wizard és camera profile

## Cél

Vezetett, kihagyható és privacy-tudatos kameraelhelyezési flow létrehozása.

## Feladatok

- Hozd létre a setup state machine-t és képernyőket.
- Támogasd a leftHandFocus, rightHandFocus, fullUpperBody és balanced profilokat.
- Készíts nagy, egyértelmű kameraábra overlayt minden profilhoz.
- Kérd be vagy olvasd a left-handed beállítást, de engedd korrigálni.
- Támogasd front/back camera választást és camera switch restartot.
- Mutasd a helyi feldolgozás és no-recording privacy állapotát.
- A setup legyen kihagyható, és ajánljon audio-only folytatást.
- Persistáld csak a választott profilt és kamerát, raw képet ne.

## Kötelező ellenőrzések

- Widget tesztek minden setup profilra.
- Permission denied flow.
- Camera switch flow fake adapterrel.
- Localization parity.

## Elfogadási feltételek

- A setup 3–5 egyszerű lépésből elvégezhető.
- A felhasználó érti, mi legyen látható.
- Kamera nélküli út elérhető.
- Nincs implicit raw capture.

## Javasolt commit

```text
feat(vision): add guided privacy-aware camera setup
```


# Kör 9 — Frame quality assessor

## Cél

Determinálni, hogy a frame alkalmas-e vision feedbackre, még landmark vagy technique inference előtt.

## Feladatok

- Implementáld a luminance, clipping, blur, camera motion és ROI coverage metrikákat.
- A blur és lighting számítás fusson downsampled grayscale képen.
- Hozz létre `VisionFrameQuality` és ablakos `VisionQualitySummary` modelleket.
- Definiálj profile-specifikus framing requirementet.
- Készíts feedback prioritás policyt, amely egyszerre egy setup problémát ad.
- A quality thresholdok konfigurálhatók és verziózottak legyenek.
- Adj synthetic fixture-eket sötét, kiégett, blur és stabil képre.
- Mérd a quality assessor latencyt low-tier eszközön.

## Kötelező ellenőrzések

- Unit fixture tesztek.
- Threshold boundary tesztek.
- Performance benchmark.
- Widget quality cue golden teszt.

## Elfogadási feltételek

- A quality assessor modell nélkül működik.
- Nem ad technikai feedbacket rossz quality mellett.
- A setup cue prioritása determinisztikus.
- A futási költség a dokumentált budgeten belül van.

## Javasolt commit

```text
feat(vision): assess framing lighting blur and stability
```


# Kör 10 — Camera és guitar calibration domain

## Cél

Verziózott, migrálható kalibrációs profil és validity policy létrehozása.

## Feladatok

- Definiáld a CameraCalibrationProfile és GuitarCalibration modelleket.
- Tárold a camera ID absztrakciót, orientationt, zoomot, setup profilt és normalizált anchorokat.
- Implementálj schema versiont és idempotens migrációt.
- Definiáld a validity és invalidation reason listát.
- Készíts calibration quality score-t.
- Hozz létre repositoryt KeyValueStore vagy később megfelelő lokális store mögött.
- Raw preview screenshot ne kerüljön a profilba.
- Írj korrupció- és régi schema teszteket.

## Kötelező ellenőrzések

- `flutter test test/features/vision/calibration`
- Storage migration tesztek.
- Round-trip JSON teszt.

## Elfogadási feltételek

- A kalibráció verziózott.
- Érvénytelen profil nem használható csendben.
- Régi vagy sérült profil kontrollált setupot kér.
- Adatmodell nem tartalmaz raw képet.

## Javasolt commit

```text
feat(vision): add versioned camera and guitar calibration
```


# Kör 11 — Manual guitar geometry calibration UI

## Cél

Megbízható production fallback létrehozása nut, bridge/body és neck polygon kézi megadásával.

## Feladatok

- Készíts touch/drag alapú anchor editort.
- Rajzold a nut, bridge/body anchorokat, centerline-t és neck polygon előnézetet.
- Korlátozd a pontokat érvényes frame területre.
- Validáld a minimum nyakhosszt, polygon területet és degenerált geometriát.
- Támogasd a nagyított precision edit módot raw fájlmentés nélkül.
- Számíts calibration qualityt és magyarázd a hibát.
- Mentsd a profilt csak explicit Save után.
- Adj Reset és Recalibrate flow-t.

## Kötelező ellenőrzések

- Widget drag tesztek.
- Golden portrait/landscape.
- Degenerált polygon unit teszt.
- Accessibility semantics teszt.

## Elfogadási feltételek

- A user képes stabil geometriát megadni.
- Hibás geometria nem menthető.
- A UI tükör- és rotation-helyes.
- A kalibráció később újranyitható és szerkeszthető.

## Javasolt commit

```text
feat(vision): add manual guitar geometry calibration
```


# Kör 12 — Hand landmark provider adapter és model manifest

## Cél

Providerfüggetlen hand landmark inference production adapter bevezetése, model integrity és fixture tesztekkel.

## Feladatok

- Implementáld a `HandLandmarkProvider` production adapterét a kiválasztott on-device megoldással.
- Mapold a provider outputját stabil StrumSight landmark ID-kre.
- Adj model manifestet checksum, input, output schema, license és evaluation referenciával.
- Validáld initializationkor az assetet és output shape-et.
- Implementálj timestampelt video/live-stream inference-t.
- A buffer konverzió legyen izolált és benchmarkolt.
- Kezeld a zero-hand, one-hand és two-hand outputot.
- Készíts fake provider és recorded output fixture adaptert CI-hez.

## Kötelező ellenőrzések

- Model manifest checksum teszt.
- Recorded output mapping teszt.
- Native init failure teszt.
- Valós eszköz inference latency benchmark.

## Elfogadási feltételek

- A domain nem függ provider API-tól.
- Model asset integrity ellenőrzött.
- Timestamp sorrend védett.
- A pipeline null/üres outputot nem hibaként, hanem nem megfigyelhető állapotként kezeli.

## Javasolt commit

```text
feat(vision): integrate on-device hand landmarks
```


# Kör 13 — Hand track assignment és temporal smoothing

## Cél

Stabil fretting/picking hand trackek létrehozása jitter és rövid occlusion mellett.

## Feladatok

- Implementálj track assignmentet pozíció, handedness confidence és előző állapot alapján.
- Különítsd el a physical hand és guitar role fogalmat.
- Adj profile-specifikus smoothingot gyors picking és lassú fretting mozgáshoz.
- Implementálj jump rejectiont és rövid gap recoveryt.
- Hosszú gap után új track ID készüljön.
- Mérd és tárold a track continuity metrikát.
- Készíts cross-hand és mirror edge case fixture-eket.
- Smoothing latency szerepeljen a performance summaryban.

## Kötelező ellenőrzések

- Pure Dart track unit tesztek.
- Property teszt az ID stabilitásra.
- Occlusion fixture.
- Fast strum fixture smoothing összehasonlítás.

## Elfogadási feltételek

- A két kéz szerepe stabil.
- A filter nem tompítja el indokolatlanul a gyors stroke-ot.
- Rövid occlusion nem okoz folyamatos ID cserét.
- Hosszú hiány explicit track lost.

## Javasolt commit

```text
feat(vision): stabilize hand tracks over time
```


# Kör 14 — Pose landmark provider és posture baseline

## Cél

Minimalizált felsőtest-pose pipeline és személyes baseline létrehozása arcelemzés nélkül.

## Feladatok

- Implementáld a PoseLandmarkProvider interfészt és production adaptert.
- Csak a szükséges váll, könyök, csukló, csípő és opcionális fej referenciát mapold.
- Arc-specifikus landmarkot ne tárolj és ne logolj.
- Futtasd a pose modellt hand modelnél alacsonyabb cadence-en.
- Implementálj visibility gate-et és baseline collector ablakot.
- Baseline csak jó setup quality és stabil frame mellett készülhet.
- Készíts posture quality és drift observation modelleket.
- Adj model manifestet és fixture teszteket.

## Kötelező ellenőrzések

- Pose mapping unit teszt.
- No-face-persistence audit.
- Baseline invalid quality teszt.
- Valós eszköz latency és thermal rövid benchmark.

## Elfogadási feltételek

- Pose pipeline külön leállítható.
- Nem történik arcfelismerés vagy arcadat persistence.
- Baseline csak valid körülményből készül.
- Low-tier cadence konfigurálható.

## Javasolt commit

```text
feat(vision): add privacy-minimized posture tracking
```


# Kör 15 — Guitar coordinate system és homography

## Cél

A camera landmarkokat stabil, gitárhoz relatív koordinátába transzformáló geometriai core létrehozása.

## Feladatok

- Implementáld a guitar u/v coordinate rendszert.
- Hozz létre homography solver és inverse modult.
- Validáld a polygon orientationt, convexityt és kondíciót.
- Mapold a hand landmarkokat guitar space-be confidence propagationnel.
- Definiáld a neck, body és picking zone régiókat.
- Készíts synthetic perspective fixture-eket.
- Írj property tesztet a mapping round-tripre.
- Degenerált vagy elvesztett geometria esetén capability degraded legyen.

## Kötelező ellenőrzések

- `flutter test test/core/geometry`
- Property homography tesztek.
- Golden overlay guitar grid.

## Elfogadási feltételek

- A gitárkoordináta pure Dart és tesztelt.
- Perspective mapping stabil valid inputon.
- Invalid geometry nem ad numerikus szemét outputot.
- Confidence megfelelően propagálódik.

## Javasolt commit

```text
feat(vision): map observations into guitar coordinates
```


# Kör 16 — Guitar geometry tracking és calibration loss

## Cél

A kézzel kalibrált gitárgeometria rövid távú követése és elmozdulás esetén biztonságos érvénytelenítése.

## Feladatok

- Implementálj feature/edge alapú vagy könnyű geometry tracker adaptert.
- A tracker ne változtassa meg korlátlanul a manual anchorokat; drift bound szükséges.
- Számíts frame-to-frame geometry confidence-et.
- Tartós confidence loss esetén állítsd le a guitar-relative metrikákat.
- Jeleníts meg Recalibrate cue-t negatív technique feedback helyett.
- A geometry source váltását és driftet rögzítsd a session summaryban.
- Készíts camera bump és guitar movement fixture szcenáriót.
- Ne implementálj még automated guitar detector modellt.

## Kötelező ellenőrzések

- Geometry drift unit teszt.
- Calibration loss state machine teszt.
- Widget recalibrate cue.
- Valós device kézi elmozdítás teszt.

## Elfogadási feltételek

- Kisebb mozgás követhető.
- Nagy mozgás recalibrationt kér.
- Elveszett geometry alatt nincs gitárspecifikus negatív feedback.
- A tracker nem sodródik észrevétlenül korlátlanul.

## Javasolt commit

```text
feat(vision): track calibrated guitar geometry safely
```


# Kör 17 — Automatikus guitar/neck detector döntési kör

## Cél

Go/no-go döntés egy saját automatikus guitar neck detector szükségességéről és megvalósíthatóságáról.

## Feladatok

- Gyűjts consentelt vagy jogtisztán használható prototípus datasetet több gitárral és fénnyel.
- Definiáld az object/line/segmentation detector lehetséges outputját.
- Készíts offline Python baseline-t legalább egy klasszikus és egy tanítható megközelítéssel.
- Mérd ROI IoU-t, anchor errort, latencyt és failure rate-et.
- Hasonlítsd össze a manual calibration idő- és hibaköltségével.
- Készíts ADR-t: no-go, experimental-only vagy production candidate.
- No-go esetén ne adj model assetet az apphoz.
- Go esetén is csak experimental flag mögött induljon.

## Kötelező ellenőrzések

- Reprodukálható evaluation script.
- Dataset manifest és consent audit.
- Benchmark report.
- Nincs consumer rollout ebben a körben.

## Elfogadási feltételek

- A döntés adatokon alapul.
- A false geometry kockázat dokumentált.
- A manual fallback megmarad.
- A production MVP nincs blokkolva model hiányán.

## Javasolt commit

```text
research(vision): evaluate automatic guitar geometry detection
```


# Kör 18 — Bal kéz metric engine

## Cél

Megfigyelhető, nagyobb léptékű bal kéz metrikák pure Dart és confidence-aware implementációja.

## Feladatok

- Implementáld a wrist deviation proxyt.
- Implementáld a hand-to-neck distance metrikát.
- Implementáld a chord-change travel pályahosszát ismert Practice eventek között.
- Implementáld a ready-position time observationt, ha a következő target ismert.
- Implementáld a sustain stability és finger spread proxykat.
- Minden metrichez add meg minimum visibilityt, ablakot és confidence formulát.
- Hozz létre synthetic landmark fixture-eket és boundary teszteket.
- A metric engine ne generáljon UI szöveget.

## Kötelező ellenőrzések

- Unit teszt minden metricre.
- NaN/Infinity guard.
- Low visibility no-observation teszt.
- Mirror/left-handed parity teszt.

## Elfogadási feltételek

- Minden metric pure Dart.
- Alacsony qualitynél nincs érvényes evidence.
- Bal- és jobbkezes mapping helyes.
- Nincs exact fret/string claim.

## Javasolt commit

```text
feat(vision): measure production-safe fretting-hand geometry
```


# Kör 19 — Jobb kéz stroke metric engine

## Cél

Audio onset köré rendezett jobb kéz mozgáspálya és konzisztenciametrikák létrehozása.

## Feladatok

- Definiáld a stroke analysis time windowt audio event előtt és után.
- Implementáld trajectory direction, amplitude, speed és linearity metrikákat.
- Implementáld down/up asymmetry és beat-to-beat consistency aggregációt.
- Implementáld picking zone relatív kategóriát.
- Különítsd el az event-level observationt és session aggregate-et.
- A wrist/elbow contribution csak semleges observation legyen.
- Készíts synthetic és recorded landmark fixture-eket.
- Sync quality hiányában csak lassú aggregate metrika legyen érvényes.

## Kötelező ellenőrzések

- Stroke fixture tesztek.
- No-audio-event teszt.
- Bad sync degradation teszt.
- Fast down/up sequence performance teszt.

## Elfogadási feltételek

- A metric audio eventhez kapcsolható.
- A direction mapping tükrözéshelyes.
- Nincs univerzális stílusítélet.
- Sync nélkül nincs event-level feedback.

## Javasolt commit

```text
feat(vision): measure picking-hand stroke consistency
```


# Kör 20 — Posture metric engine és safety policy

## Cél

Baseline-hoz viszonyított, nem diagnosztikai testtartás-observation és biztonságos insight alap létrehozása.

## Feladatok

- Implementáld a shoulder asymmetry, torso lean, elbow drift és optional neck proxy metrikákat.
- Minden metric legyen relatív baseline-hoz, ahol lehetséges.
- Definiáld a minimum visible durationt és session drift windowt.
- Hozz létre safety language code-okat és tiltott claim teszteket.
- Fájdalom-bejelentés kezelését a Tutor safety policyvel hangold össze.
- Ne generálj orvosi diagnózist vagy kockázati jóslatot.
- Készíts posture fixture-eket különböző camera angle-lel.
- Low pose confidence esetén `notObservable` legyen.

## Kötelező ellenőrzések

- Metric unit tesztek.
- Safety phrase/claim guard teszt.
- Baseline missing teszt.
- Camera perspective fixture.

## Elfogadási feltételek

- A feedback semleges és bizonyíték-alapú.
- Nincs egészségügyi claim.
- Baseline nélkül nincs hamis abszolút ítélet.
- Alacsony visibility nem pontozódik.

## Javasolt commit

```text
feat(vision): add baseline-relative posture observations
```


# Kör 21 — Audio–vision clock mapping és latency calibration

## Cél

A camera observationok és audio strum eventek megbízható közös session időre helyezése.

## Feladatok

- Definiáld a VisionClock, AudioClock és ClockMapping contractokat.
- Implementáld a timestamp offset és opcionális drift becslést.
- Készíts kalibrációs flow-t több pengetés/taps eventtel.
- Használj outlier rejectiont és confidence score-t.
- Rögzíts capture, inference és observation latency komponenseket.
- Definiáld a sync quality bucketeket benchmark alapján konfigurálhatóan.
- Event-level metric csak good vagy excellent sync mellett engedélyezett.
- Készíts fake clock és drift fixture teszteket.

## Kötelező ellenőrzések

- Clock mapping unit teszt.
- Drift property teszt.
- Outlier calibration teszt.
- Valós Android audio+camera calibration benchmark.

## Elfogadási feltételek

- A mapping monotonic clockot használ.
- Wall clock nem része a szinkronnak.
- Bad sync explicit degraded.
- Az offset újramérhető session közben.

## Javasolt commit

```text
feat(vision): synchronize camera observations with audio events
```


# Kör 22 — Vision observation fusion és evidence engine

## Cél

A landmark-, geometry-, quality- és audioadatokból verziózott VisionEvidence előállítása.

## Feladatok

- Implementáld az observation fusion pipeline-t.
- Definiáld metrikánként a minimum frame countot, visible durationt és gap policyt.
- Propagáld a confidence-et a model, quality, geometry és sync komponensekből.
- Hozz létre stable evidence ID-t és provenance-t.
- Kezeld az observed, inferred, notObservable és experimental állapotokat.
- A pipeline ne emitáljon duplikált evidence-et ugyanarra az ablakra.
- Adj determinisztikus fixture snapshotokat.
- Mérd a pipeline memóriáját hosszabb fake sessionben.

## Kötelező ellenőrzések

- Evidence golden snapshot.
- Confidence propagation unit teszt.
- Gap/occlusion teszt.
- 10 perces synthetic session memory teszt.

## Elfogadási feltételek

- Evidence visszakövethető a provenance alapján.
- Nincs single-frame negatív evidence.
- Confidence komponensek dokumentáltak.
- Hosszabb session nem növeli korlátlanul a memóriát.

## Javasolt commit

```text
feat(vision): fuse observations into traceable evidence
```


# Kör 23 — Feedback policy és realtime cue budget

## Cél

VisionEvidence-ből korlátozott, stabil és lokalizálható VisionInsight előállítása.

## Feladatok

- Implementáld a verziózott feedback policy registryt.
- Minden insight code-hoz add meg required capabilityt, confidence thresholdot, minimum durationt és cooldown-t.
- Setup és observability cue legyen prioritásban a technikai cue előtt.
- Egy időben legfeljebb egy realtime cue legyen aktív.
- Session summaryban legfeljebb két elsődleges technikai fókusz legyen.
- Adj pozitív improvement insightot csak összehasonlítható ablakokból.
- Készíts localization kulcsokat angolul és magyarul.
- Írj tiltott claim és low-confidence suppression teszteket.

## Kötelező ellenőrzések

- Policy unit tesztek.
- Cooldown clock teszt.
- Localization parity.
- Golden summary fixture.

## Elfogadási feltételek

- A policy determinisztikus.
- Low-confidence negatív cue elnyomódik.
- Nincs cue spam.
- A domain nem tartalmaz hardcoded UI mondatokat.

## Javasolt commit

```text
feat(vision): convert evidence into bounded coaching cues
```


# Kör 24 — Vision session controller és realtime overlay

## Cél

A teljes vision state machine, preview overlay és session lifecycle összekapcsolása fake és production adapterrel.

## Feladatok

- Implementáld a VisionSessionControllert immutable state-tel.
- Kösd össze permission, camera lease, quality, calibration, inference, fusion és feedback lépéseket.
- Készíts preview overlayt hand/pose/guitar quality chipekkel.
- A detailed skeleton csak debug vagy user toggle mellett jelenjen meg.
- Implementáld Pause, Resume, Recalibrate és Stop műveleteket.
- Route leave és app background cancellation legyen tesztelt.
- A finalization egyszer emitáljon resultot.
- A UI thread ne végezzen pixelfeldolgozást vagy inference-et.

## Kötelező ellenőrzések

- Widget state machine tesztek.
- Integration fake frame streammel.
- Route leave resource teszt.
- UI jank/profile valós eszközön.

## Elfogadási feltételek

- A teljes flow setupból completed állapotba jut.
- Minden hiba kontrollált UI-t kap.
- Nincs frame buffer provider state-ben.
- App background azonnal leállítja a kamerát.

## Javasolt commit

```text
feat(vision): deliver lifecycle-safe realtime coaching session
```


# Kör 25 — Practice Engine vision integráció

## Cél

Vision observation hozzáadása kiválasztott Practice gyakorlatokhoz az audio scoring megőrzésével.

## Feladatok

- Implementáld a VisionPracticeContractot.
- Adj legalább három pilot gyakorlatot: Small Strum Motion, Down/Up Symmetry, Chord Change Economy.
- Bővítsd a Practice session resultot opcionális VisionSessionResult referenciával.
- Audio scoring maradjon változatlan és vision nélkül teljes.
- Vision quality rossz állapotban a gyakorlat audio-only módra váltson.
- Speed Builder vision gate csak feature flag mögött induljon.
- Készíts session summary dimension UI-t.
- Írj integrációs tesztet vision unavailable, degraded és good állapotra.

## Kötelező ellenőrzések

- Practice unit és widget tesztek.
- Audio score parity fixture.
- Vision fallback integration.
- Valós device pilot exercise.

## Elfogadási feltételek

- A Practice Engine nem függ a camera implementation belsejétől.
- Vision nélkül nincs regresszió.
- Vision eredmény külön dimenzió.
- Pilot gyakorlatok capability gate-elve működnek.

## Javasolt commit

```text
feat(practice): integrate optional vision technique evidence
```


# Kör 26 — Song Trainer vision integráció

## Cél

Szakasz- és loop-szintű vision summary létrehozása teljesítményvédett módban.

## Feladatok

- Implementáld a SongVisionAdaptert közös session/section/loop ID-kkal.
- A–B loop iterációnként aggregáld a stroke consistencyt és hand travel metrikát.
- Posture drift csak hosszabb szakasznál fusson.
- Device tier alapján állítsd a vision cadence-et.
- Thermal degradation esetén állj át audio-only módra a dal megszakítása nélkül.
- A result UI mutassa, mely loopban volt elég vision quality.
- Ne változtasd meg a Song Trainer audio transport timingját.
- Készíts performance profile-t backing track + audio scoring + vision kombinációra.

## Kötelező ellenőrzések

- Song loop integration teszt.
- Transport timing parity.
- Thermal fake teszt.
- Valós eszköz 5 perces loop benchmark.

## Elfogadási feltételek

- A Song Trainer timing nem regresszál.
- Vision quality looponként ismert.
- Thermal fallback nem állítja le a dalt.
- Low-tier eszközön nincs kényszerített vision.

## Javasolt commit

```text
feat(songs): add performance-aware vision coaching
```


# Kör 27 — AI Tutor és Analysis evidence adapterek

## Cél

A vision eredmények minimális, privacy-safe és claim-guardolt elérhetővé tétele a Tutor és Analysis rendszereknek.

## Feladatok

- Implementáld a TutorVisionContextAdaptert csak aggregate, insight, confidence és observability mezőkkel.
- Implementáld a claim guardot, amely evidence nélküli vizuális állítást blokkol.
- Implementáld az Analysis vision reference adaptert közös session idővel.
- Definiáld a cross-modal inferred insight provenance-t.
- Raw frame, teljes landmark stream és arcpont ne kerüljön a tutor contextbe.
- Készíts minimization snapshot tesztet.
- Adj deterministic fallback szöveget notObservable állapotra.
- Frissítsd a Chapter 5/7 integrációs dokumentációt.

## Kötelező ellenőrzések

- Tutor context snapshot.
- Claim guard unit teszt.
- No-raw-data audit.
- Analysis reference round-trip teszt.

## Elfogadási feltételek

- A tutor csak valid evidence-ből beszél visionről.
- A context adatminimalizált.
- Cross-modal insight inferredként jelölt.
- Analysis és Vision session összekapcsolható.

## Javasolt commit

```text
feat(ai): expose grounded vision evidence to tutor and analysis
```


# Kör 28 — Persistence, privacy control és törlés

## Cél

Verziózott VisionSessionResult tárolás és teljes felhasználói kontroll megvalósítása raw media nélkül.

## Feladatok

- Hozd létre a VisionSessionRepositoryt és schema migrationt.
- Ments aggregate metricet, insightot, capabilityt, qualityt és model versiont.
- Alapértelmezetten ne ments full landmark timeline-t.
- Készíts Settings privacy panelt vision history, calibration és Lab data kezelésére.
- Implementálj egy-session és delete-all műveletet.
- Implementálj JSON exportot raw image nélkül.
- Korrupció esetén csak az érintett record legyen karanténban.
- Teszteld account/cloud disabled állapotban a nulla hálózati kérést.

## Kötelező ellenőrzések

- Repository unit tesztek.
- Schema migration.
- Delete integration.
- Export privacy snapshot.
- Network spy teszt.

## Elfogadási feltételek

- Raw frame nincs persistence-ben.
- A user törölhet minden vision adatot.
- Sérült record nem törli a teljes historyt.
- Vision használat nem generál automatikus network requestet.

## Javasolt commit

```text
feat(vision): persist privacy-safe session summaries
```


# Kör 29 — Device tier, performance és thermal hardening

## Cél

Valós eszközökön fenntartható működés, audio-priority degradation és mérhető teljesítménykapuk létrehozása.

## Feladatok

- Implementáld a VisionDeviceTier benchmarkot.
- Definiáld tierenként a hand FPS, pose cadence, input resolution és overlay cadence profilokat.
- Implementáld a dropped frame és inference freshness monitort.
- Integráld a thermal state adaptert, ahol platform támogatja; egyébként használj performance heuristicot.
- Audio deadline romlásakor lépcsőzetesen degradáld a Vision pipeline-t.
- Rögzíts performance summaryt a sessionben.
- Készíts 10 és 30 perces soak teszt tervet.
- Dokumentáld az unsupported device viselkedést.

## Kötelező ellenőrzések

- Low/mid/high tier benchmark.
- 10 perces soak legalább két eszközön.
- Audio DSP latency összehasonlítás vision off/on.
- Thermal/fake degradation teszt.
- Memory leak ellenőrzés.

## Elfogadási feltételek

- Vision nem rontja csendben az audio engine-t.
- A device tier determinisztikus és mérhető.
- Thermal állapotban graceful fallback történik.
- Hosszabb session után nincs folyamatos memóriaemelkedés.

## Javasolt commit

```text
perf(vision): add device-tiered thermal-safe inference
```


# Kör 30 — Dataset, evaluation, CI és Epic lezárás

## Cél

A Computer Vision feature minőségi kapuinak, model integrityjének, real-device validationjének és végső dokumentációjának lezárása.

## Feladatok

- Hozd létre a vision dataset manifestet és consent dokumentációt.
- Készíts evaluation harness-t hand tracking, quality, geometry, metric és false feedback mérésére.
- Adj model checksum és output schema CI gate-et.
- Adj architecture guardot raw frame persistence és cross-feature belső import ellen.
- Futtasd a teljes Flutter és backend regressziót.
- Futtasd a valós eszközös test matrix kritikus részét.
- Készíts `docs/sdd/epic-05-completion-report.md` fájlt.
- Frissítsd a README-t, HANDOFF-ot, privacy leírást és model cardokat.
- Dokumentáld a production-supported és experimental metrikákat.
- Minden nem validált feature maradjon flag-off.

## Kötelező ellenőrzések

- `dart format --output=none --set-exit-if-changed lib test tool`
- `flutter analyze lib/ test/ tool/`
- `flutter test`
- `flutter test test/property`
- `Android instrumented camera suite`
- `Model manifest integrity`
- `Valós device benchmark report`
- `Backend regresszió, ha érintett`

## Elfogadási feltételek

- Minden CI zöld.
- A kamera minden lifecycle útvonalon felszabadul.
- Raw média alapértelmezetten nem mentődik és nem töltődik fel.
- False feedback gate dokumentált és teljesült a production metrikákra.
- Vision off állapotban teljes audio parity van.
- A production és experimental capability lista végleges.
- Elkészült az Epic completion report.

## Javasolt commit

```text
docs(vision): close Epic 5 computer vision platform
```


---

# 39. Epic 5 végső Definition of Done

Az Epic kizárólag akkor tekinthető késznek, ha minden productionként megjelölt capability az alábbi követelményeket teljesíti.

## Platform és lifecycle

- [ ] Android camera permission és usage flow működik.
- [ ] iOS permission contract és plist előkészítés helyes.
- [ ] Egyszerre egy camera owner lehetséges.
- [ ] Route leave után a kamera felszabadul.
- [ ] App background után a kamera felszabadul.
- [ ] Camera interruption kontrollált state-et ad.
- [ ] Start/stop versenyhelyzetek teszteltek.
- [ ] Nincs callback dispose után.

## Privacy

- [ ] Raw frame alapértelmezetten nem mentődik.
- [ ] Raw videó nem töltődik fel automatikusan.
- [ ] Arcadat nem kerül persistence-be.
- [ ] A user törölheti a vision historyt.
- [ ] A user törölheti a calibration profile-t.
- [ ] Vision kikapcsolható az audiofunkciók elvesztése nélkül.
- [ ] Lab capture külön build/flag és consent mögött van.

## Kamera és setup

- [ ] Preview rotation- és mirror-helyes.
- [ ] Latest-frame backpressure működik.
- [ ] Quality assessor jelzi a fény-, blur-, framing- és occlusion problémát.
- [ ] Manual guitar calibration működik.
- [ ] Invalid calibration nem használható.
- [ ] Calibration loss recalibrationt kér.

## Inference és geometria

- [ ] Hand model manifest és checksum ellenőrzött.
- [ ] Pose model manifest és checksum ellenőrzött.
- [ ] Hand tracking ID stabilitás tesztelt.
- [ ] Guitar coordinate mapping tesztelt.
- [ ] Homography degenerált inputon fail-closed.
- [ ] Low confidence observation nem eredményez negatív feedbacket.
- [ ] Experimental fine-grained capability flag-off alapértelmezett.

## Audio–vision

- [ ] Közös monotonic session time létezik.
- [ ] Clock offset és quality mérhető.
- [ ] Event-level vision metric csak megfelelő sync mellett készül.
- [ ] Vision terhelés nem rontja a DSP-t a megengedett budgeten túl.
- [ ] Audio-priority degradation működik.

## Coaching

- [ ] VisionEvidence verziózott és provenance-szel rendelkezik.
- [ ] VisionInsight determinisztikus policyből készül.
- [ ] Egy időben legfeljebb egy realtime cue aktív.
- [ ] Session summary legfeljebb két elsődleges fókuszt ad.
- [ ] NotObservable állapot explicit.
- [ ] Nincs exact fret/string claim production capability nélkül.
- [ ] Nincs orvosi diagnózis vagy sérülési jóslat.

## Integráció

- [ ] Practice Engine audio-only módban változatlan.
- [ ] Practice Vision result külön dimenzió.
- [ ] Song Trainer timing nem regresszál.
- [ ] Tutor csak strukturált evidence-et kap.
- [ ] Tutor claim guard aktív.
- [ ] Analysis közös session ID-val kapcsolható.

## Teljesítmény és minőség

- [ ] Device tier meghatározás működik.
- [ ] Low-tier graceful degradation működik.
- [ ] Thermal fallback működik.
- [ ] 10 perces soak teszt nem mutat korlátlan memóriaemelkedést.
- [ ] Model latency dokumentált.
- [ ] False feedback rate dokumentált.
- [ ] Bal- és jobbkezes parity ellenőrzött.
- [ ] Több fény- és gitártípus tesztelve.

## CI és dokumentáció

- [ ] Format, analyze és Flutter tesztek zöldek.
- [ ] Property tesztek zöldek.
- [ ] Camera platform suite zöld a támogatott Android eszközökön.
- [ ] Model integrity gate zöld.
- [ ] Dataset manifest és consent policy dokumentált.
- [ ] Completion report elkészült.
- [ ] README és HANDOFF frissült.
- [ ] Nem validált capability flag-off maradt.

---

# 40. Kiadási minimum

Az első production Vision release minimuma:

1. opcionális camera permission;
2. megbízható setup és quality feedback;
3. manual guitar calibration;
4. hand tracking;
5. basic posture tracking;
6. guitar-relative coordinate system;
7. jobb kéz stroke consistency;
8. bal kéz hand-to-neck és travel metrika;
9. audio–vision sync quality;
10. session végi, legfeljebb két insight;
11. Practice Engine pilot integráció;
12. teljes camera-off fallback;
13. raw media nélküli privacy alap;
14. device tier és thermal degradation;
15. dokumentált false feedback evaluation.

Az alábbiak nem blokkolják az első release-t:

- exact fret/string recognition;
- automated guitar detector;
- palm mute detection;
- pick grip classification;
- barre contact analysis;
- iOS teljes feature parity, ha az Android-first scope ezt külön jelzi;
- generatív vizuális magyarázat.

---

# 41. Az Epic eredménye

Az Epic 5 végére a StrumSight rendelkezik egy olyan camera- és vision platformmal, amely:

- offline és privacy-first;
- nem ment automatikusan videót;
- nem függ egyetlen konkrét modellprovidertől;
- stabilan kezeli a kamera lifecycle-t;
- mérhető quality és capability állapotot ad;
- gitárhoz relatív koordinátában dolgozik;
- összekapcsolható az audioeseményekkel;
- nem pontozza a nem látható technikát;
- kis, célzott Practice gyakorlatokban használható;
- Song Trainerben performance-aware módon fut;
- evidence-et ad az AI Tutornak és az Analysis rendszernek;
- fokozatosan bővíthető későbbi fine-grained modellekkel;
- false feedback ellen minőségkapukkal védett.

A fejezet lezárása után a roadmap következő eleme:

```text
Chapter 7 — Epic 6: Audio Analysis 2.0
```

Mivel a Chapter 7 specifikáció már elkészült, a Computer Vision implementáció után annak vision adapter és cross-modal insight részeit a tényleges Epic 5 contractokhoz kell igazítani. Ez nem jogosítja fel a fejlesztőt az Audio Analysis teljes újratervezésére; csak a dokumentált integrációs pontokat kell frissíteni.
