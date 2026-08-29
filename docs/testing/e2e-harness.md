# E2E test harness (`test/e2e/`)

- **Kör:** E12-R11 (Chapter 12, Kör 11)
- **ADR:** [`0472`](../adr/0472-e2e-flow-harness-runs-in-the-flutter-test-host.md)
- **Brief:** [`docs/rounds/e12-r11-end-to-end-test-harness.md`](../rounds/e12-r11-end-to-end-test-harness.md)

## What this is

Two determinstic, CI-reproduced vertical-slice tests that pump the **real**
`StrumSightApp` widget tree — real `routerProvider`, real screens, real
`tester.tap`/`pumpAndSettle` — in the `flutter test` host:

- `test/e2e/first_practice_offline_test.dart` — fresh install → onboarding
  (Skip) → Practice Hub → Quick Start → Setup → Session → Finish → the
  finished session's history record is loadable through the same repository
  the production recorder writes through.
- `test/e2e/returning_user_restart_test.dart` — a practiced session's history
  survives the ADR 0472 §0.0/R6 "app restart" sequence: unmount the widget
  tree → dispose the first `ProviderContainer` → a **new** container + **new**
  router on the **same** `InMemoryKeyValueStore` instance → pump
  `StrumSightApp` again.

Supporting fixtures (`test/support/`, new this round):

- `fake_clock.dart` — `HarnessClock`, the single deterministic time source
  both flows drive the practice session's `countIn`/`running`/`finishing`
  transitions with. Wraps the existing `FakePracticeSessionClock` +
  `FakePracticeTickSource` so a caller can never advance one without the
  other ([L122](../LESSONS.md#l122)).
- `fake_network_guard.dart` — `FakeNetworkGuard` blocks and records every
  outgoing path a build can reach: the Dio `HttpClientAdapter`, `dart:io`'s
  `HttpOverrides`, and platform channels (a process-wide catch-all via
  `TestDefaultBinaryMessenger.allMessagesHandler`, not one named channel —
  [L453](../LESSONS.md#l453)).
- `e2e_harness.dart` — the deterministic bootstrap profile: builds on the
  **existing** 12 `test/support/` fakes (`fakeAudioOverrides`,
  `FakeStrumEngine`/`FakeTunerEngine`, `FakeTokenStore`,
  `InMemoryKeyValueStore`) plus the two files above, and the shared
  `runFirstPracticeSession` / `restartE2eApp` / history-snapshot helpers both
  flow files call.

## What this covers

- The real navigation chain a Practice V2 session travels: Hub → Setup →
  Session, driven by actual widget taps against actual routes
  (`AppRoutes.practiceHub` / `practiceSetup` / `practiceSession`), not a
  constructor-injected shortcut.
- The real production provider graph for a session: `practicePrepareSinkProvider`
  → the `practiceSessionControllerProvider` auto-dispose family →
  `PracticeHistoryRecorder` → `LocalPracticeHistoryRepository` →
  `KeyValueStore`. Only the clock, tick source, and the platform-boundary
  adapters (mic, engines, feedback output) are swapped for fakes — same
  pattern `practice_production_wiring_test.dart` and
  `test/app/offline_network_guard_test.dart` already use.
- That the flow never depends on the network: three dedicated cells drive
  each of the guard's three paths directly, and the whole first-practice
  flow asserts the guard never tripped.
- Determinism: both flows run their whole sequence twice, independently, and
  compare a persisted-result snapshot with `expect(second, equals(first))` —
  a machine check, not a "the gate happened to pass twice" argument.
- That the three harness source files never smuggle in a real
  `DateTime.now()`/`Random(` read (a static, source-level cell — a hidden
  real timestamp would not necessarily show up as a behavioural flake).

## What this deliberately does NOT cover

Per ADR 0472 (Következmények) — these stay on the **device-level** path, a
capability-proven **later** round (after the Ch13 device matrix):

- A real microphone, a real `AudioCapture`, or any DSP running on real audio.
- Real on-device persistence (`shared_preferences` / secure storage plugins)
  — this lane always injects `InMemoryKeyValueStore`/`FakeTokenStore`.
  `KeyValueStore`'s own contract is covered elsewhere
  (`test/core/storage/`); this lane only proves the app's *wiring* to it,
  including across the "restart" sequence.
- Any OS permission dialog (microphone, notifications) — the permission
  gateway is always a scripted fake here (`FakeMicrophonePermissionGateway`).
  `test/features/onboarding/` and the device matrices cover the real primer.
- Native plugin behaviour (`flutter_secure_storage`, `permission_handler`,
  `package_info_plus`, …) — every plugin-backed provider this lane touches is
  overridden before the first frame.
- Multi-device / multi-OS variation (screen size, platform channel quirks,
  real timing jitter) — `docs/manual-testing/practice-engine-device-matrix.md`
  is the source of truth for that surface.
- `integration_test`/`flutter drive` coverage — ADR 0472 D1: no Android SDK
  on this box, no emulator CI job today. Introducing that package is
  explicitly out of scope for this round (§5.1) and is a later,
  capability-proven round's decision, gated on a CI job landing in the SAME
  round.

## Running it

```bash
tools/round-gate.sh test/e2e/first_practice_offline_test.dart test/e2e/returning_user_restart_test.dart test/app/offline_network_guard_test.dart
```

The existing `test/app/offline_network_guard_test.dart` stays in the gate
list unedited (A6) — this round's guard is an addition, not a replacement.
