# Telemetry event catalog

- **Status:** contract only — no event is emitted from `lib/features/**` in
  this round (E12-R19, ADR 0484 §0.1). This document must stay in sync with
  `lib/core/telemetry/telemetry_event.dart`, which is the source of truth for
  the enum values; if the two disagree, the Dart file wins.

## Why the catalog is closed

`TelemetryEvent` carries no free-form field: no `Map<String, dynamic>`, no
`dynamic`, no `Object?`, no free `String`. Every dimension below is a fixed
enum. A raw prompt, an audio/video sample or free user text has no field to
occupy — the prohibition is structural (ADR 0484 D1), and the redactor in
`telemetry_redactor.dart` is only the second line of defence.

## `TelemetryEventName`

| Name | Category | Meaning |
|---|---|---|
| `appLaunched` | lifecycle | The app process started. |
| `screenViewed` | lifecycle | A screen became the visible route. |
| `chordDetectionCompleted` | detection | An on-device chord-detection pass over a recorded/live clip finished. |
| `strumDirectionDetected` | detection | An on-device strum-direction classification finished. |
| `tunerSessionCompleted` | session | A tuner session ended. |
| `practiceSessionCompleted` | session | A practice/exercise session ended. |
| `tutorTurnCompleted` | tutor | An AI tutor turn reached a terminal state. |
| `settingsChanged` | settings | A user-visible setting changed. |
| `diagnosticsUploadAttempted` | diagnostics | An opt-in Lab-mode diagnostics upload was attempted. |

## `TelemetryEventCategory`

`lifecycle`, `detection`, `session`, `tutor`, `settings`, `diagnostics` — the
grouping the release dashboard rolls events up by, so a new event name is
always assigned to one of these, never a new ad-hoc string.

## `TelemetryOperationResult`

`success`, `failure`, `cancelled`, `unknown` — the outcome of the reported
operation. This is a per-event result, distinct from the release-dashboard
`unknown` verdict defined in `docs/operations/slo.yaml` (ADR 0484 D3): an
event can honestly report `result: unknown` (e.g. the process was torn down
mid-operation) without that meaning the SLO measuring it is missing.

## `TelemetryCapability` (optional)

`onDeviceMl`, `onDeviceDsp`, `cloudTutor`, `cloudSync` — which capability the
reported operation ran under. Closed for the same reason as the event name: a
free "model/version" string would reopen the free-text hole D1 closes.

## `TelemetryDurationBucket`

A measured duration is always reported as a bucket, never as a raw
millisecond count (ADR 0484 D1, acceptance cell A4) — a raw duration is a
de-facto free-form channel. Boundaries are **inclusive on the lower edge**:

| Bucket | Range (ms) |
|---|---|
| `ms0To250` | `[0, 250)` |
| `ms250To500` | `[250, 500)` |
| `ms500To1000` | `[500, 1000)` |
| `ms1000To3000` | `[1000, 3000)` |
| `ms3000To10000` | `[3000, 10000)` |
| `ms10000AndAbove` | `[10000, infinity)` |

`TelemetryDurationBucket.fromMilliseconds` is the single conversion point —
callers never construct a bucket by hand.

## What this round does NOT do

- No event is emitted anywhere in `lib/features/**` — wiring emission into a
  screen/controller is a later round (SDD Ch12 rollout, ADR 0484 §0.1).
- No sink in this round reaches the network — see `telemetry_sink.dart` and
  ADR 0484 D5.
- No telemetry-consent switch exists on the tree yet; `ConsentGatedTelemetrySink`
  takes its consent read as an injected function so wiring the real switch
  later does not require touching this contract (ADR 0484 D4).
