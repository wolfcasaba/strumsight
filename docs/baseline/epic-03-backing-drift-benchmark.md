# Epic 03 — backing drift initial benchmark

**Status:** initial adapter benchmark complete; on-device confirmation pending.

## Evidence and method

The production adapter is `audioplayers 6.8.0`. Its `AudioPlayer` constructs a
`FramePositionUpdater` at
`~/.pub-cache/hosted/pub.dev/audioplayers-6.8.0/lib/src/audioplayer.dart:171`.
`FramePositionUpdater` requests a position update on every rendered frame
(`lib/src/position_updater.dart:44-55`); the same package also exposes a
`TimerPositionUpdater(interval:)` (`:24-42`). The adapter therefore declares
the render-frame cadence as its explicit position-sample precision rather than
treating the stream as the transport clock.

The selected initial `PlaybackCapabilities.positionPrecision` is **17 ms**:
the integral ceiling of one 60 Hz render frame (16.7 ms). This is an adapter
property benchmark, not an assertion about physical speaker or guitar timing.
`SongTransport` remains anchored to its monotonic clock; position events only
produce drift reports.

## Initial policy

| Policy cell | Precision multiple | Duration | Action |
|---|---:|---:|---|
| tolerated sample | 2× | 34 ms | retain monotonic anchor |
| resync boundary | 3× | 51 ms | request measure-boundary resync |
| hard-resync sample | 4× | 68 ms | seek safely to master position |

The deterministic policy uses the 3× value (51 ms) as its threshold: values
below it are tolerated, equality is the boundary-resync cell, and values above
it take the hard-resync path. `backing_drift_test.dart` covers
threshold−1 ms, threshold, and threshold+1 ms with a fake player and fake
monotonic clock. This proves the policy derivation and boundary behaviour, not
device output latency.

## On-device evidence

**Pending user device gate.** Measure actual `onPositionChanged` jitter and
audible resync behaviour on supported Android hardware before any claim about
physical playback synchronisation. CI and deterministic fakes do not replace
that measurement.
