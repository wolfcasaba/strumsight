# ADR 0056 — Exclusive microphone session: busy failure, not steal

- **Status:** Accepted
- **Date:** 2026-07-29
- **Round:** E01-R09 (SDD Ch2, Kör 9)
- **Required by:** SDD Ch2 Kör 9 §9.2, which mandates that the second-owner
  behaviour be recorded in an ADR.

## Context

Three features record from the one microphone — Live (strum/chord detection),
Tuner (YIN) and the Analyze clip recorder — and two more are planned (latency
calibration, diagnostics capture). Until this round each engine owned its own
`MicCapture`, asked for the permission itself, and started `audio_streamer`
directly. Nothing coordinated them:

- opening the Tuner from Live could hand a second capture to the same device;
- a start that failed halfway could leave a live PCM subscription behind;
- a missing permission platform channel was treated as **granted**, so a
  broken channel read as consent;
- backgrounding the app relied on each screen's `dispose` to stop the mic.

The device-level result of two owners is platform-dependent (one stream goes
silent, or the second start throws) — i.e. exactly the class of silent no-op
this project keeps paying for.

## Decision

### 1. One coordinator, one lease

`AudioSessionCoordinator` (one per `ProviderScope`) hands out a single
`AudioSessionLease` to one `AudioOwner` (`live`, `tuner`, `analyzeRecorder`,
`latencyCalibration`, `diagnostics`). The check-and-take runs synchronously
before the first `await`, so two overlapping `acquire` calls cannot both win.

### 2. The second owner gets a controlled busy failure — it does NOT steal

`acquire` returns `Failure(AudioFailure(code: 'audio.session_busy'))` while
another owner holds the session (SDD §9.2 offers stealing as the alternative;
the default it recommends is the busy failure, and that is what we take).

**Why not stealing:** stopping the current owner from underneath leaves that
screen's UI claiming it is listening while its stream is dead — the failure is
invisible exactly where the user is looking. A busy failure, by contrast,
surfaces on the *requesting* screen, which is where the user's attention just
went, and it is `retryable: true` because closing the other screen frees the
mic. In practice the navigation shape (Live and Tuner are separate routes whose
providers are `autoDispose`) means the holder is normally gone before the new
owner asks; the busy path is the safety net, not the common case.

### 3. Backgrounding revokes, resuming does not restart

`AudioLifecycleGuard` (mounted for the app's lifetime) calls
`revokeActive()` on `paused` / `hidden` / `detached`. Revoking runs the owner's
own teardown (cancel the subscription, kill the DSP isolate) and then frees the
lease — even if that teardown throws, so a crashed owner cannot lock the
microphone forever. `inactive` is deliberately excluded: it also fires for a
transient system overlay, and killing the capture there would end a session on
a notification-shade pull.

Resume never restarts capture. The Live screen shows itself as paused after a
background trip, so the user restarts listening deliberately.

### 4. An unknown permission state is never a grant

`MicrophonePermissionGateway` maps a missing/broken plugin channel to
`MicrophonePermissionState.unavailable` → `permission.unavailable`, not to
`granted`. Tests inject a fake gateway instead of relying on the absent
channel (which is what previously made "no channel" mean "granted").

## Consequences

- Every mic user goes through `MicCapture`, which enforces permission → lease →
  capture and unwinds all three on any failure path.
- Widget tests that render a mic screen must override
  `microphonePermissionGatewayProvider` (see `test/support/fake_audio.dart`);
  without an override the real gateway reports `unavailable` and the screen
  shows the permission banner — which is the honest production behaviour.
- A second owner's busy failure is a *localisable code*, so a future UI can say
  "the tuner is using the microphone" instead of failing silently.
- DSP output is untouched: this round moved lifecycle, not signal processing.
