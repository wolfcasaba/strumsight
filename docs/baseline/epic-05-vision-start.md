# Epic 5 Computer Vision — kiinduló baseline

- **Rögzítve:** 2026-08-06
- **Forrásbaseline:** `main` @ `41a0b29` (Epic 4 lezárva, E04-R24 merge után)
- **Kör:** E05-R01 — Vision baseline, capability audit és alapozó ADR-ek
- **Motor:** DeepSeek v4 Pro (`deepseek/deepseek-v4-pro`, Kilo-profil)
- **Branch:** `codex/e05-r01-vision-baseline-and-adrs`
- **Határ:** ez mérhető kiindulási állapot, dokumentált ADR-döntések és metric-
  blueprint; **production kód nem változik**, kamera-dependency nincs bevezetve.

## 1. Jelenlegi állapot — mért, `41a0b29`

Minden állítás alatt a mérést előállító **nyers parancs és kimenet**.

### 1.1 Kamera-dependency: nincs

```bash
$ rg -n "camera" pubspec.yaml
(nincs találat, exit code 1)
```

A `pubspec.yaml` `dependencies` blokkjában egyetlen `camera*` csomag sem
szerepel. Vision- vagy ML-inference library (`mediapipe`, `tflite`,
`mlkit`, `opencv`, `pose_landmark`, `hand_tracking`, `object_detection`)
szintén nincs:

```bash
$ rg -n "vision|mediapipe|tflite|mlkit|opencv|pose|landmark|hand_tracking|object_detection" pubspec.yaml
(nincs találat, exit code 1)
```

### 1.2 Android permission: RECORD_AUDIO, INTERNET, POST_NOTIFICATIONS, RECEIVE_BOOT_COMPLETED

A manifest nem deklarál `CAMERA` permissiont.

```bash
$ rg "<uses-permission" android/app/src/main/AndroidManifest.xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
```

### 1.3 iOS: nincs NSCameraUsageDescription

```bash
$ rg -n "NSCameraUsageDescription" ios/
(nincs találat, exit code 1)

$ rg "UsageDescription" ios/
ios/Runner/Info.plist:	<key>NSMicrophoneUsageDescription</key>
```

Az iOS `Info.plist` csak mikrofon usage descriptiont tartalmaz.

### 1.4 Nincs vision könyvtárstruktúra

```bash
$ ls -d lib/core/camera/ lib/core/geometry/ lib/core/ml/ lib/features/vision/
ls: cannot access 'lib/core/camera/': No such file or directory
ls: cannot access 'lib/core/geometry/': No such file or directory
ls: cannot access 'lib/core/ml/': No such file or directory
ls: cannot access 'lib/features/vision/': No such file or directory
(exit code 2 — egyik sem létezik)
```

### 1.5 Meglévő feature-k: 18

```bash
$ ls lib/features/
ai_tutor  analyze  auth  chords  diagnostics  learn  library  live
metronome  onboarding  practice  progress  settings  share  song_trainer
songs  streak  tuner

$ ls lib/features/ | wc -l
18
```

### 1.6 Flutter / Dart környezet

```bash
$ dart --version
Dart SDK version: 3.12.2 (stable) (Tue Jun 9 01:11:39 2026 -0700) on "linux_arm64"

$ flutter --version | head -1
Flutter 3.44.2 • channel stable • https://github.com/flutter/flutter.git
```

## 2. Meglévő, újrahasználandó minták

A vision feature az alábbi, **már működő** elemekre épülhet. Minden hivatkozás
a base commit (`41a0b29`) disken látható fájljaira mutat.

### 2.1 Audio lifecycle — a camera lifecycle precedense

Az audio session-ownership, lifecycle guard és dispose minta, amelyhez a
camera lifecycle-nak igazodnia kell:

```bash
$ find lib/core/audio/lifecycle -type f | sort
lib/core/audio/lifecycle/audio_lifecycle_guard.dart
lib/core/audio/lifecycle/audio_session_coordinator.dart
lib/core/audio/lifecycle/audio_session_lease.dart
```

- **`AudioSessionCoordinator`** — exkluzív session-owner, egyszerre egy
  birtokos (ADR 0056). A kamera is egy exkluzív erőforrás; a
  `CameraSessionCoordinator` ennek a mintának a megfelelője lesz.
- **`AudioSessionLease`** — élettartam-kötött bérlet; dispose-kor az erőforrás
  felszabadul. A kamera-frame stream is ezt a mintát követi: a lease
  élettartama alatt él a frame-stream, dispose után nincs további capture.
- **`AudioLifecycleGuard`** — app-pause / route-leave esetén az audio
  leáll. A kamera ugyanezt a guard-mintát kapja (ADR 0178 §3: app-pause
  → kamera azonnal leáll).

### 2.2 Permission gateway

```bash
$ find lib/core/platform -type f | sort
lib/core/platform/app_lifecycle.dart
lib/core/platform/microphone_permission.dart
lib/core/platform/platform_providers.dart
lib/core/platform/screen_wakelock.dart
```

- **`MicrophonePermissionGateway`** + `MicrophonePermissionState`
  (`granted` / `denied` / `permanentlyDenied`) — a kamera-permission
  gateway (`CameraPermissionGateway`) ezt a szerződést követi.
- **`PermissionFailure`** (`lib/core/foundation/app_failure.dart`) —
  a kamera-permission megtagadása is ezt a típust használja.

### 2.3 Audio capture factory

```bash
$ find lib/core/audio/capture -type f | sort
lib/core/audio/capture/audio_capture.dart
lib/core/audio/capture/audio_capture_factory.dart
```

- **`AudioCapture` + `AudioCaptureFactory`** — platform-absztrakció:
  interfész + gyártófüggvény. A camera capture (`CameraCapture` +
  `CameraCaptureFactory`) ugyanezt a mintát követi (ADR 0180: domain
  platform-független).

### 2.4 Model asset manifest

A jelenlegi model asset-ek:

```bash
$ sed -n '/^flutter:/,/^[a-z]/p' pubspec.yaml | rg "assets/ml/"
    - assets/ml/strum_crnn.bin
    - assets/ml/strum_crnn_live.bin
    - assets/ml/strum_crnn_live_3c.bin
    - assets/ml/chord_crnn.bin
```

A vision model asset-ek ugyanebbe a mintába illeszkednek: az `assets/ml/`
alá kerülnek, a `pubspec.yaml` assets szekciójában deklarálva, checksum- és
verziókövetéssel (SDD §30, AGENTS.md §9).

### 2.5 Routing

```bash
$ find lib/ -name "*route*" -o -name "*router*" | sort
lib/app/routing/app_route.dart
lib/app/routing/app_router.dart
lib/app/routing/route_guards.dart
lib/features/practice/presentation/practice_route_args.dart
```

A vision screen-ek a meglévő `app_router.dart` GoRouter konfigurációjába
illeszkednek; a route-guard minta a kamera-permission ellenőrzésére is
használható.

### 2.6 Teszt infrastruktúra

```bash
$ ls -d test/features/ test/core/ test/app/ test/property/
test/app/
test/core/
test/features/
test/property/
```

A vision tesztek a `test/core/camera/`, `test/core/geometry/`,
`test/core/ml/` és `test/features/vision/` alá kerülnek.

## 3. Architekturális döntések — hivatkozás

A hat kötelező vision ADR-t az orchestrátor (Claude) írta a pre-flightban.
Ebben a körben nem módosulnak; az implementáció a következő körökben az
alábbi döntésekre épül:

| ADR | Tárgy | Kulcsdöntés |
| --- | --- | --- |
| [0178](../adr/0178-vision-privacy-by-default.md) | Privacy by default | Raw frame csak memóriában, feldolgozás után azonnal elengedve |
| [0179](../adr/0179-vision-capability-aware-feedback.md) | Capability-aware feedback | Minden insight: `requiredCapability` + `confidence` + `observability`; hiányzó megfigyelhetőség → `notObservable`, nem gyengébb ítélet |
| [0180](../adr/0180-vision-android-first-camera-strategy.md) | Android-first camera strategy | Epic Android-on szállít; iOS contract szintjén; domain platform-független |
| [0181](../adr/0181-vision-manual-calibration-fallback.md) | Manual calibration fallback | Production út a kézi kalibráció; automatikus detektor csak experimental flag mögött |
| [0182](../adr/0182-vision-audio-priority-degradation.md) | Audio-priority degradation | Audio deadline romlásakor a vision degradálódik, sosem az audio |
| [0183](../adr/0183-vision-no-raw-frame-persistence.md) | No-raw-frame persistence | Persistence csak aggregátum (`VisionSessionResult`): insight + capability + model-verzió |

## 4. Metrika-lista — production-supported vs experimental

A lista forrása: SDD Ch6 §5.5, §7, §8.3–8.5, a Kör 18–20 metric engine
specifikációi, valamint az ADR 0179 (capability-aware feedback) és ADR 0181
(manual calibration fallback).

### 4.1 Production-supported metrics

| Metrika | `requiredCapability` | Minimum observability előfeltétel |
| --- | --- | --- |
| **Right-hand stroke zone** — pengetési zóna (bridge / soundhole / neck) | `handTracking` | Legalább egy kéz landmark ≥ 0.6 confidence, a pengető kéz és a gitártest látható |
| **Right-hand stroke direction consistency** — le-/felütés arány konzisztenciája | `handTracking` + `audioSync` | Audio event + vizuális mozgás timestamp sync ≤ 50 ms |
| **Right-hand stroke amplitude** — pengetési amplitúdó relatív változása | `handTracking` + `calibration` | Kalibrált gitártest reference + kéz landmark ≥ 0.6 |
| **Left-hand hand-to-neck position** — bal kéz nyakhoz viszonyított helyzete | `handTracking` + `guitarGeometry` | Kézzel kalibrált gitárnyak-geometria + kéz landmark ≥ 0.6 |
| **Left-hand travel economy** — bal kéz mozgásgazdaságossága (távolság/idő) | `handTracking` + `guitarGeometry` | Kézzel kalibrált gitárnyak-geometria + legalább két frame kéz landmark ≥ 0.6 |
| **Left-hand ready position time** — akkordváltás előtti kézpozíció-idő | `handTracking` + `audioSync` | Audio chord event + kéz landmark ≥ 0.6, a chord event előtti 200 ms ablak |
| **Posture shoulder symmetry** — vállszimmetria | `poseTracking` + `calibration` | Kalibrált reference-pose + váll landmark ≥ 0.7 |
| **Posture torso angle** — törzs dőlésszöge | `poseTracking` + `calibration` | Kalibrált reference-pose + törzs landmark ≥ 0.7 |
| **Camera quality — blur** | `cameraQuality` | Frame-él-detektálás ≥ küszöb (Laplacian variance) |
| **Camera quality — lighting** | `cameraQuality` | Frame átlagos luminancia a [40, 240] tartományban |
| **Camera quality — occlusion** | `cameraQuality` | Kéz landmark visibility ≥ 0.5 a várt landmark-ok legalább 60%-ára |
| **Audio-vision sync offset** | `audioSync` | Legalább 3 audio event + vizuális mozgás páros, páranként ≤ 100 ms offset |

### 4.2 Experimental metrics

| Metrika | `requiredCapability` | Minimum observability előfeltétel |
| --- | --- | --- |
| **Exact fret position** — bal kéz ujjának bund-pozíciója | `fineFretTracking` + `guitarGeometry` | Kalibrált gitárnyak + fret-vonalak detektálva, kéz landmark ≥ 0.8, nincs takarás |
| **Exact string identification** — melyik húron van az ujj | `fineFretTracking` + `guitarGeometry` | Kalibrált gitárnyak + húrvonalak detektálva, kéz landmark ≥ 0.8, nincs takarás |
| **Fingertip pressure estimation** — ujjbegy-nyomás becslése | `fineFretTracking` + `guitarGeometry` | Nagy felbontású közeli kamera, ujjbegy-texture változás detektálva |
| **Automatic guitar geometry detection** — automatikus gitárgeometria-detektálás | `autoGeometryDetection` | Csak experimental flag mögött; a manual fallback mindig elérhető (ADR 0181) |
| **Fine-grained picking pattern** — pengetési minta ujjszintű felbontásban | `fineHandTracking` | Nagy FPS (≥ 60) + közeli kamera, kéz landmark ≥ 0.8 |

### 4.3 Future (jelenleg nem tervezett)

| Metrika | Indoklás |
| --- | --- |
| Exact string/fret recognition from raw image | A perspektivikus, takart, eltérő fényű és hangszerű képek miatt az MVP-ben nem cél (SDD §1) |
| Pain / injury diagnosis | Orvosi diagnózis tilos (AGENTS.md §5) |
| Body type / skin color / age inference | Érzékeny jellemzőkből következtetés tilos (SDD §1, AGENTS.md §5) |

## 5. Feature flagek — tervezett

A flag-ek ebben a körben **nem kerülnek be** (SDD Kör 1 utolsó feladatpontja;
az E05-R03 feladata). A lista az SDD §36.1-ből:

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

## 6. Ismert korlátok az Epic kezdetén

Az SDD §3.2 listája alapján, a base commiton (`41a0b29`) mérve:

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

## 7. Következő kör

E05-R02 — Camera technology spike és döntési kapu (SDD Kör 2):
camera plugin kiválasztása, frame stream prototípus, első camera
permission spike.
