# ADR 0184 — Vision camera capture stack

- **Status:** Accepted conditionally (E05-R02, 2026-08-06); device evidence is PENDING
- **Epic:** [Chapter 6 — Epic 5: Computer Vision](../sdd/06-epic-05-computer-vision.md) §5.3, §5.7, §11
- **Context ADRs:** [0178](0178-vision-privacy-by-default.md),
  [0180](0180-vision-android-first-camera-strategy.md),
  [0182](0182-vision-audio-priority-degradation.md),
  [0183](0183-vision-no-raw-frame-persistence.md)
- **Evidence:** [candidate evaluation](../baseline/epic-05-camera-stack-evaluation.md)
  and [device runbook](../manual-testing/vision-camera-spike-runbook.md)

## Context

Epic 5 needs an Android capture path that can preview and deliver frames to a
future platform-neutral `CameraFrame` contract. The current repository has no
camera dependency or permission; this docs-only round adds neither. The choice
must be evidence-led because a capture stack can create hidden frame queues,
timestamp ambiguity, lifecycle leaks, and audio contention.

The official Flutter [`camera` package](https://pub.dev/packages/camera)
provides preview and Dart image-buffer streaming. Its endorsed Android
implementation is CameraX-backed, as documented by
[`camera_android_camerax`](https://pub.dev/packages/camera_android_camerax).
Flutter's package documentation also assigns app lifecycle handling to the
caller. Android's official [CameraX ImageAnalysis guide](https://developer.android.com/media/camera/camerax/analyze)
documents native analysis and lifecycle binding, but does not prove a Flutter
adapter's backpressure or timestamp behavior on StrumSight devices.

## Decision

1. **Default path: C1, the official Flutter `camera` plugin with its endorsed
   CameraX Android implementation.** E05-R06 may add it only behind the future
   platform adapter; no plugin API/type may enter the vision domain (ADR 0180).
2. **The decision is conditional and falsifiable.** The selected adapter must
   implement latest-frame semantics (queue depth at most 1) and forward strictly
   monotonic retained frame timestamps. The E05-R03 `CameraFrame` ownership
   contract remains independent and is not defined here.
3. **C2, a direct CameraX platform channel, replaces C1** if the device runbook
   records a C1 failure of either latest-frame backpressure (M05) or monotonic
   timestamps (M10). C3, the hybrid path, is not a default and may be selected
   only if it proves one camera client plus the same lifecycle/copy/timestamp
   thresholds as C1.
4. **Numerical acceptance thresholds:**
   - 20 preview starts: p95 first-frame init **≤ 2000 ms** (M01);
   - five-minute stream: every 30-second window has processed FPS **≥ 15.0**
     (M02);
   - 20 stops: every close reaches zero active camera clients **≤ 2000 ms**
     (M06), and the post-close RSS is no more than **20 MiB** over baseline
     after 30 seconds;
   - retained timestamps are strictly increasing over **1000** frames and
     each sequence gap has a corresponding drop record (M10).

Failure is a decision input, not a reason to change the threshold silently. The
device matrix requires the C1 mandatory rows to pass on two different Android
devices before C1 is treated as production evidence.

## Consequences

- The future adapter explicitly owns lifecycle release on route leave and app
  background; it must not enable background image streaming. This satisfies the
  active-foreground camera rule in ADR 0178.
- Vision uses latest-frame drop/degradation and never changes audio DSP
  parameters to compensate for camera load (ADR 0182).
- Raw frames remain in memory only and may not be logged, uploaded, or persisted
  (ADRs 0178 and 0183).
- `pubspec.yaml`, Android permissions, the camera spike, and production adapter
  are follow-up work. This decision alone authorizes none of them.

## Rejected alternatives

- **Direct CameraX platform channel now.** Rejected as default: it duplicates a
  maintained Flutter integration before the C1 falsification criteria have been
  measured.
- **Hybrid preview plus custom analysis now.** Rejected as default: two
  camera-facing paths increase client, copying, and lifecycle risk; it needs its
  own positive device evidence.
- **Unconditional plugin choice.** Rejected: package capability documentation
  does not establish StrumSight's latest-frame or timestamp requirements on real
  devices.
