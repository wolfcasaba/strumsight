# Epic 5 — camera capture stack evaluation (E05-R02)

- **Status:** conditional decision baseline; no device measurement has been
  recorded yet
- **Scope:** Android-first capture layer only; no dependency, production code, or
  Android manifest change is made by this document
- **Decision consumer:** [ADR 0184](../adr/0184-vision-camera-capture-stack.md)
- **Measurement procedure:** [camera spike runbook](../manual-testing/vision-camera-spike-runbook.md)

## 1. Evidence labels and candidates

`O1` is the official [Flutter `camera` package documentation](https://pub.dev/packages/camera):
it documents preview, Dart image-buffer streaming, manual lifecycle ownership,
BSD-3-Clause licensing, and the endorsed Android implementation. `O2` is the
official [`camera_android_camerax` documentation](https://pub.dev/packages/camera_android_camerax):
it identifies the Android implementation as CameraX-backed and documents its
YUV420/NV21 streamed-image behavior and BSD-3-Clause licence. `O3` is the
official Android [CameraX ImageAnalysis guide](https://developer.android.com/media/camera/camerax/analyze),
which describes lifecycle binding, image analysis, analyzer replacement, and
the `ImageProxy` rotation metadata. `O4` is the Android [CameraX configuration
guide](https://developer.android.com/media/camera/camerax/configuration), which
documents target-rotation updates and metadata. `Mxx` means **MÉRENDŐ
eszközön**, with the named runbook row as the source; it is deliberately not a
performance claim.

| ID | Candidate | Boundary |
| --- | --- | --- |
| C1 | Official Flutter `camera` package with its endorsed `camera_android_camerax` implementation | Flutter adapter owns preview and image stream; E05-R03 defines the pure-Dart `CameraFrame` contract. |
| C2 | Custom Android platform channel built directly on CameraX `Preview` + `ImageAnalysis` | Flutter owns only the channel/contract; Android owns CameraX binding and frame transfer. |
| C3 | Hybrid: `camera` preview plus a custom CameraX analysis stream | Two camera-facing paths share the device; only permissible if the runbook demonstrates no competing-session or copy regression. |

## 2. Required criteria table

The same `Mxx` identifiers occur in the runbook and device matrix. A `MÉRENDŐ`
cell is not a positive claim about a candidate. C2 inherits CameraX capability
only where `O3`/`O4` state it; its channel and ownership implementation remains
measured.

| Criterion | C1 — official `camera` | C2 — custom CameraX channel | C3 — hybrid | Source / runbook link |
| --- | --- | --- | --- | --- |
| Init time | MÉRENDŐ p50/p95 from controller create to first frame | MÉRENDŐ p50/p95 from bind to first frame | MÉRENDŐ p50/p95, including both paths | M01 |
| Frame FPS | Dart image stream is documented; sustained delivered/processed FPS is MÉRENDŐ | CameraX `ImageAnalysis` exists; sustained delivered/processed FPS is MÉRENDŐ | MÉRENDŐ separately for preview and analysis | O1, O3, M02 |
| Pixel format / `YUV_420_888` | Streamed `yuv420` is documented; exact Android plane mapping is MÉRENDŐ | CameraX analysis supports `ImageProxy`; exact requested/output format is MÉRENDŐ | MÉRENDŐ; record whether both paths expose the same format | O2, O3, M03 |
| Rotation metadata | MÉRENDŐ at the Flutter boundary | CameraX exposes analysis rotation metadata; channel forwarding is MÉRENDŐ | MÉRENDŐ for both paths and orientation changes | O3, O4, M04 |
| Buffer copies | MÉRENDŐ Dart/native copy count per retained latest frame | MÉRENDŐ channel serialization/copy count | MÉRENDŐ; must include duplicate-preview cost | M05 |
| Close time / release | Plugin lifecycle is caller-owned; stop/dispose release latency is MÉRENDŐ | CameraX lifecycle unbind/release latency is MÉRENDŐ | MÉRENDŐ for closing both sessions | O1, O3, M06 |
| Front-camera mirror | MÉRENDŐ preview and analysis coordinates | MÉRENDŐ CameraX-to-contract coordinate transform | MÉRENDŐ preview/analysis parity | M07 |
| Portrait / landscape change | MÉRENDŐ controller behavior; app must own lifecycle | CameraX target rotation is configurable; transform is MÉRENDŐ | MÉRENDŐ for both paths | O1, O4, M08 |
| Pause / resume | Package requires application lifecycle handling; reopen/release is MÉRENDŐ | Lifecycle binding is documented; app behavior is MÉRENDŐ | MÉRENDŐ; no second competing camera session | O1, O3, M09 |
| Monotonic frame timestamps | MÉRENDŐ; no official Flutter timestamp monotonicity guarantee is used | MÉRENDŐ across channel transfer | MÉRENDŐ across both paths | M10 |
| Maintenance / licence | Flutter.dev published, BSD-3-Clause | AndroidX CameraX official documentation; verify exact dependency licence at adoption | Combines C1 and C2 maintenance surfaces | O1, O2, O3, M11 |
| `win32` conflict risk | Current package dependency graph is not yet resolved in this repo; MÉRENDŐ by `pub deps` before adoption | No Dart camera package is planned; Gradle resolution is MÉRENDŐ | MÉRENDŐ for both Dart and Gradle graphs | M12 |

## 3. Provisional comparison and conclusion

`C1` is the default because it gives one Flutter-maintained integration that
already exposes both preview and streamed image buffers, while retaining an
Android CameraX-backed implementation. This is a conditional selection, not an
unmeasured performance result. The app must still explicitly manage lifecycle
transitions, as the package documentation requires.

`C2` is the fallback when C1 cannot satisfy either of the two non-negotiable
evidence requirements in the runbook: latest-frame backpressure or monotonic
timestamps. `C3` has no default path: a second camera-facing pipeline raises
ownership/copy risk and is selected only if M05, M06, M09, and M10 pass with the
same thresholds as C1 and demonstrate one bound camera session.

No candidate may send or persist raw frames. The eventual adapter must preserve
the privacy boundary in [ADR 0178](../adr/0178-vision-privacy-by-default.md),
the Android-only production scope in [ADR 0180](../adr/0180-vision-android-first-camera-strategy.md),
and audio-first, latest-frame degradation in [ADR 0182](../adr/0182-vision-audio-priority-degradation.md).
