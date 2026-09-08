# E09-R28a — Vision frame pipeline: measured facts and tunable numbers

Scope: what the R28a round wired, which numbers it introduced, and what a
later round must measure before trusting them. Everything below was derived by
reading the code in this repository; **nothing here was executed** (this box
has no Dart/Flutter SDK — `docs/execution/remote-container-environment.md`).

Related: ADR 0179 (capability-aware feedback), ADR 0181 (manual calibration is
the production geometry source), ADR 0183 (no raw frame persistence),
ADR 0184 (camera capture stack), ADR 0185/0186 (landmark models, both still
`deferred`).

---

## 1. What was broken (measured, pre-round)

| fact | evidence |
|---|---|
| every camera frame was discarded | `vision_session_controller.dart` `_onFrame` incremented a counter and returned |
| `reportQuality` / `reportRealtimeCue` had zero callers in `lib/` | only two test files called them |
| the finished session was dropped | `visionSessionResultListenerProvider` defaulted to `(_) {}` |
| there was no camera preview anywhere | `CameraPreview` / `Texture(` had zero hits in `lib/` |
| the persisted manual calibration was never read at session time | `beginCalibration()` only flipped a status enum |
| the luminance plane could be sheared silently | `plugin_camera_capture._copyPlanes` concatenated planes and dropped `Plane.bytesPerRow` |

## 2. The stride defect, precisely

Android's Y plane may be padded: `Plane.bytesPerRow` (the row stride) can
exceed the frame width. The flat buffer a capture adapter delivers is then
**not** a `width * height` image.

`GrayscaleFrame.isWellFormed` only checks `luminance.length >= width * height`,
which a padded buffer always satisfies, and `FrameQualityAssessor` indexes
`y * width + x`. A padded frame therefore produced a **sheared** image and
plausible-looking quality numbers, with no error anywhere.

`ResolutionPreset.medium` is typically 640x480, where `rowStride == width`.
That is why the defect would pass on one device and corrupt on another.

**Fix.** `CameraFrame` now carries `rowStride` (populated from
`Plane.bytesPerRow` when it exceeds the width, `null` otherwise), and
`lib/features/vision/data/pipeline/yuv_luminance.dart` is the single place
that de-pads. `_copyPlanes` still concatenates verbatim on purpose: the chroma
planes have their own strides and pixel strides, and de-padding them blindly
would corrupt them.

Regression cells: `test/features/vision/data/pipeline/yuv_luminance_test.dart`
(byte-exact, including the "read as unpadded" shear) and the padded-versus-
unpadded equality cell in `vision_frame_pipeline_test.dart`.

## 3. Numbers this round introduced

These are **starting values, not measurements**. A later round retunes them
against real frames and records the result here.

| constant | value | where | reasoning |
|---|---|---|---|
| `VisionSessionGeometry.defaultRoiDilation` | 1.6 | `data/pipeline/vision_session_geometry.dart` | the calibration polygon hugs the neck; the fretting hand sits beside and above it, so the raw bounding box crops the very thing the region exists to hold |
| `FrameQualityPipeline.defaultPublishInterval` | 500 ms | `data/pipeline/vision_frame_pipeline.dart` | must stay above the policy's 250 ms `minimumDuration`, or every candidate is rejected for a too-short evidence window and the session emits nothing |
| `FrameQualityPipeline.defaultWindowFrameLimit` | 90 | same | only bounds the pathological case of a capture whose timestamps stop advancing; a window normally clears on publish |
| `FrameQualityPipeline.notObservableConfidence` | 1.0 | same | confidence **in the observability claim**, not in the player: with no landmark model active the fretting/picking/posture metrics are structurally unreachable, so the claim is certain |
| `FrameQualityPipeline.modelVersion` | `deferred` | same | both entries in `assets/ml/model_manifest.json` are `deferred`; the provenance says so rather than naming a model that never ran |
| `visionSessionModelVersionsProvider` | `{hand_landmarker: deferred, pose_landmarker: deferred}` | `application/vision_session_controller.dart` | the session codec rejects an empty provenance map |

The window cadence is driven by **frame timestamps** (`CameraTimestamp`), not
by the wall clock, so the publish boundary is deterministic in tests and
immune to a device clock change mid-session.

## 4. What the pipeline may and may not say

* Frame quality (framing, lighting, blur, stability, ROI coverage) is measured
  from the luminance plane and is real.
* Hand and pose stay `notObservable` — that is the measured truth while no
  landmark model runs, not a placeholder.
* Guitar state comes from the persisted manual calibration, evaluated with
  `CalibrationValidity` against the same runtime context the editor saved it
  with (`guitarCalibrationContextFrom`, one function, two call sites).
* The only insight code it can propose is `InsightCode.setupNotObservable`,
  and it travels through the production `FeedbackPolicyEngine` + `CueBudget`.
  `SetupOnlyInsightClassifier` is fail-closed: `observed`, `inferred` and
  `experimental` evidence produce **no** candidate at all.

## 5. Architecture placement

`tool/check_architecture.dart` forbids the raw payload types (`VisionImage`,
`GrayscaleFrame`, `Uint8List`, `ByteData`, `ByteBuffer`, `VisionPixelFormat`)
under `lib/features/vision/data/persistence/` and inside provider-state class
bodies under `lib/features/vision/application/`. The pipeline touches pixels,
so it lives in `lib/features/vision/data/pipeline/` and hands the application
layer only immutable summaries (`VisionPipelineUpdate`).

The session controller exposes the preview as a **getter**
(`VisionSessionController.previewSource`), never as a state field: a `Widget`
in the audited summary-only state object would be a live platform handle.

**Noted gap (not fixed here).** The guard covers `data/persistence/**` and
provider-state bodies in `application/**`, but not `presentation/**`. A debug
overlay that cached a frame would slip through it.

## 6. Golden neutrality

`visionPreviewBuilderProvider` resolves to `null` unless the running session's
capture adapter implements `CameraPreviewSource`. Only `PluginCameraCapture`
does; `FakeCameraCapture` and every seeded controller do not. The six pinned
Vision PNGs (`e13_r30_vision_{setup,coach_stage,result}_{compact,compact_scale2}`)
and the `vision_session` / `vision_setup` / `vision_result` cells of the
variant matrix therefore render the identical `surfaceSunken` box, and the
session screen keeps the pre-round widget tree exactly when the preview is
`null` (the `Stack` only appears when there is something to put behind the
overlay).

## 7. Left for the model round (R28b)

* A real landmark runtime, and a classifier that replaces
  `SetupOnlyInsightClassifier` behind the same `VisionInsightClassifier`
  interface.
* Guitar-relative metrics: `GuitarLandmarkMapper` needs landmarks, and the
  calibration this round wires is only half of its input.
* Picking metrics need audio onsets (`StrokeWindow.cut`); until then
  `SyncQuality.poor` is recorded honestly and no picking claim is possible.
* Measured replacements for every number in §3, plus the APK size delta.

## 8. Over-promising copy (reported, not changed)

The Today hub's Vision card promises more than the app can do. Exact strings,
unchanged by this round:

* `lib/l10n/base/app_en.arb:3227` — `todayHubVisionCardMessage`:
  "Use your camera for guided finger-placement feedback."
* `lib/l10n/base/app_hu.arb:3149` — `todayHubVisionCardMessage`:
  "Használd a kamerát az ujjazat visszajelzéséhez."

Rendered at `lib/features/today/screens/today_hub_screen.dart:368-370`
whenever `flags.visionEnabled` is true. There is no finger-placement feedback:
no landmark model runs, so the session can only report setup quality and
whether the guitar is calibrated. The wording needs to change (or the claim
needs a model) — the Today hub is owned by another round, so this is a report,
not an edit.
