# E05-R03 — Core camera contract, fake infrastruktúra és vision feature flagek

- **Státusz:** PLANNING (pre-flight lezárva 2026-08-06, kód olvasva: main @ `7b3cf05`)
- **SDD-kör:** [`docs/sdd/06-epic-05-computer-vision.md`](../sdd/06-epic-05-computer-vision.md) Kör 3; §8, §11.1, §36.1
- **Branch:** `codex/e05-r03-core-camera-contract-and-fake`
- **Előfeltétel:** **E05-R01, E05-R02 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/core/camera/camera_capture.dart",
  "lib/core/camera/camera_frame.dart",
  "lib/core/camera/camera_format.dart",
  "lib/core/camera/camera_timestamp.dart",
  "lib/core/camera/camera_failure.dart",
  "lib/core/camera/fake_camera_capture.dart",
  "lib/core/foundation/app_failure.dart",
  "lib/app/config/feature_flags.dart",
  "test/core/camera/camera_contract_test.dart",
  "test/core/camera/fake_camera_capture_test.dart",
  "test/app/feature_flags_test.dart",
  "docs/rounds/e05-r03-core-camera-contract-and-fake.md",
]
gate_tests = [
  "test/core/camera",
  "test/app/feature_flags_test.dart",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** `origin/main` + E05-R01/R02 merge; olvasd újra
> `lib/core/audio/capture/audio_capture.dart` (a capture-contract precedense),
> `lib/core/foundation/app_failure.dart` (`FailureCode` mai enum-értékei) és
> `lib/app/config/feature_flags.dart` (Epic 4 után mely mezők vannak).
> Nincs ÚJ ADR (0161/0163 bővítése). PREPARED→PLANNING, brief commit előbb.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**Pre-flight (2026-08-06, main @ `7b3cf05`) — nincs tartalmi revízió, mért
megerősítés:**

- `lib/core/audio/capture/audio_capture.dart` precedens megerősítve: interfész
  `start`/`stop`, `Future<int> start(...)`, dobott hibából `AppFailure` a
  hívónál — a §2 leírása pontos.
- `lib/core/foundation/app_failure.dart` `FailureCode` jelenlegi értékei
  (`audioSessionBusy`, `permissionMicrophoneDenied`, `permissionUnavailable`,
  …) megerősítve — additív bővítés, ütközés nincs.
- `lib/app/config/feature_flags.dart` jelenlegi 9 mező (`accountEnabled`,
  `diagnosticsEnabled`, `labModeAvailable`, `practiceEngineV2Enabled`,
  `migratedLearnEnabled`, `practiceDetailedHistoryEnabled`,
  `songTrainerV2Enabled`, `aiTutorEnabled`, `aiTutorCloudEnabled`) megerősítve;
  `hashCode` valóban csak az első 6-ot hashelja, `==`/`toString` teljes — a §2
  állítása pontos.

Nincs ÚJ ADR (0161/0163 bővítése).

## 1. Cél

Platformfüggetlen, **teljesen tesztelhető** camera capture contract +
determinisztikus fake, production plugin nélkül; és a teljes vision
feature-flag készlet **default OFF** állapotban.

## 2. Jelenlegi állapot (mért, `5d082dc`)

- Nincs `lib/core/camera/`. A precedens `lib/core/audio/capture/audio_capture.dart`
  + `audio_capture_factory.dart` — ugyanaz a minta (interfész + fake +
  `AppResult<T>` hibakezelés) másolandó, nem újratervezendő.
- `lib/core/foundation/app_failure.dart` tartalmazza az `AppFailure` hierarchiát
  és a `FailureCode` enumot (`audioSessionBusy`, `permissionMicrophoneDenied`,
  `permissionUnavailable` …) — a camera hibakódok **ide, additívan** kerülnek.
- `lib/app/config/feature_flags.dart`: `accountEnabled`, `diagnosticsEnabled`,
  `labModeAvailable`, `practiceEngineV2Enabled`, `migratedLearnEnabled`,
  `practiceDetailedHistoryEnabled`, `songTrainerV2Enabled`, `aiTutorEnabled`,
  `aiTutorCloudEnabled`. A `hashCode` ma **nem** tartalmazza az utolsó négy
  mezőt — a bővítésnél az `==` és a `toString` teljessége a mérce (a `hashCode`
  hiányos volta meglévő állapot; javítása megengedett, elhagyása nem hiba).
- `songTrainerV2Enabled` a precedens arra, hogy egy rollout-flag **minden**
  környezetben OFF, `nonProd`-tól függetlenül — a vision flagek is ilyenek.

## 3. Scope

**Benne:** `CameraCapture` interfész (start/stop/dispose, frame stream),
`CameraFrame` **explicit ownership** modellel, `CameraFormat`/orientation enumok,
`CameraTimestamp` (monotonic), camera `FailureCode`-ok, `FakeCameraCapture`
determinisztikus, ütemezett frame-stream + injektálható hibákkal (busy,
unavailable, initialization, frame failure, interruption), és a 11 vision flag.

**Kívül — TILOS:** bármely camera plugin/`pubspec.yaml` (E05-R06), permission
(R04), coordinator (R05), transform (R07), UI, Riverpod provider.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `lib/core/camera/camera_capture.dart` | ÚJ | capture contract |
| `lib/core/camera/camera_frame.dart` | ÚJ | frame + ownership |
| `lib/core/camera/camera_format.dart` | ÚJ | pixel/orientation enumok |
| `lib/core/camera/camera_timestamp.dart` | ÚJ | monotonic időbélyeg |
| `lib/core/camera/camera_failure.dart` | ÚJ | camera hibatérkép |
| `lib/core/camera/fake_camera_capture.dart` | ÚJ | determinisztikus fake |
| `lib/core/foundation/app_failure.dart` | meglévő | **csak additív** `FailureCode` |
| `lib/app/config/feature_flags.dart` | meglévő | 11 vision flag, default OFF |
| `test/core/camera/*`, `test/app/feature_flags_test.dart` | ÚJ/meglévő | tesztek |
| `docs/rounds/e05-r03-*.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más; `docs/rag`; DSP; más kör briefje. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **A contract nem importálhat konkrét camera plugint** és nem tartalmazhat
   platform-specifikus típust (ADR 0163). **NEM elfogadható:** `dynamic` mögé
   rejtett platform-objektum a `CameraFrame`-ben.
2. **Frame ownership:** a `CameraFrame` bufferje **csak a callback szinkron
   törzsében** érvényes; a callback visszatérése után a hozzáférés hiba. Az
   API-nak ezt **dokumentálnia és tesztelnie** kell (`isValid`/`assertValid`
   vagy azzal egyenértékű, de nem néma). **NEM elfogadható:** „a hívó úgyis
   vigyáz" megjegyzés teszt nélkül.
3. **`close` idempotens**, és close után minden callback/stream-esemény
   **elutasított** (nem csendben elnyelt): a fake és a contract-teszt is ezt méri.
4. **Flagek (11 db, default OFF minden környezetben, `nonProd`-tól függetlenül,
   dart-define override NÉLKÜL):** `visionEnabled`, `visionSetupEnabled`,
   `visionHandTrackingEnabled`, `visionPoseTrackingEnabled`,
   `visionGuitarGeometryEnabled`, `visionPracticeIntegrationEnabled`,
   `visionSongIntegrationEnabled`, `visionTutorIntegrationEnabled`,
   `visionAnalysisIntegrationEnabled`, `visionExperimentalFineFretEnabled`,
   `visionLabCaptureEnabled`. **NEM elfogadható:** bármelyik alapból ON, vagy
   `nonProd`-hoz kötve.
5. **`usesNetwork` NEM változhat** egyetlen vision flagtől sem (ADR 0161):
   a vision offline képesség — ezt teszt méri.
6. **Nincs raw frame Riverpod state-ben** — ebben a körben provider sem készül.

## 6. Acceptance criteria

- [ ] **Lifecycle-mátrix teszt:** start→frame→close; close→close; start közbeni
      cancel; close utáni frame-esemény; interruption közben close — mind az
      **öt** cella külön teszt, mind a fake-en fut.
- [ ] **Hiba-mátrix:** busy / unavailable / initializationFailure / frameFailure
      / interruption → mind külön `FailureCode`-ra képződik, és a mapping
      tesztje **nem** fogad el `granted`-szerű default-ot (a mikrofon-gateway
      `unavailable`-szabályának analógja).
- [ ] **Ownership-teszt:** a callback után használt buffer **hibát ad** (nem
      csendben nullát). A reviewer eldobható mutációja: az érvényesség-ellenőrzés
      kiszedése → a teszt pirosra vált.
- [ ] **Flag-teszt mátrix:** mind a 11 flag `false` `production`, `lab` és
      `development` környezetben is; és `usesNetwork` értéke változatlan.
- [ ] A `test/core/architecture_dependency_test.dart` zöld, az allowlist **nem
      bővül**.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/core/camera test/app/feature_flags_test.dart
```

Külön processzek, nincs `&&`/pipe/`tail`. CI-dispatch/PR/merge = orchestrátor.

## 8. Implementációs sorrend

1. RED: lifecycle- és hiba-mátrix, ownership, flag-mátrix tesztek.
2. Enumok + `CameraFrame` + `CameraTimestamp` + failure mapping.
3. `CameraCapture` + `FakeCameraCapture`.
4. Flagek; gate.

## 9. Kockázatok

- **A fake „túl kedves" lesz** és nem tud hibát produkálni → a későbbi körök
  nem tudnak edge-case-t tesztelni. Ellenszer: a hiba-mátrix acceptance.
- **A `FailureCode` enum bővítése** exhaustive `switch`-eket törhet máshol:
  `rg -n "FailureCode\." lib test` az érintett helyekre; a meglévő viselkedés
  nem írható át — ha egy meglévő teszt elbukik, az **megállás és jelentés**.

**STOP:** plugin-hozzáadás, provider-létrehozás vagy mércegyengítés helyett
dokumentált brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e05-r03-core-camera-contract-and-fake-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
