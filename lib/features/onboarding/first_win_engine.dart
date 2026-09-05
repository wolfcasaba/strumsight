import 'dart:async';

import '../live/public.dart';

/// The first-win mini Stage's confidence source (SDD Ch13 Kör 16, brief §3/
/// P2).
///
/// The lifecycle contract mirrors `liveFrameProvider`
/// (`lib/features/live/providers/live_providers.dart:19-24`): [stop] is
/// idempotent and always safe to call from a provider's `ref.onDispose`.
abstract interface class OnboardingFirstWinEngine {
  /// One confidence reading (0.0–1.0) per attempt.
  Stream<double> get confidence;

  void start();

  Future<void> stop();
}

/// The production engine (ADR 0534 D3): adapts the shared
/// `strumEngineProvider` instance's frame stream into the Stage's
/// per-attempt confidence stream (`LiveFrame.confidence`,
/// `lib/features/live/model/live_frame.dart:83`). Errors on the underlying
/// frame stream (denied permission, busy mic, motor failure) pass through
/// unchanged — `Stream.map` forwards error events — so the Stage's
/// `AsyncValue` sees them too (D5).
///
/// [start]/[stop] delegate straight to the wrapped [StrumEngine] without
/// disposing it: the engine instance is shared with the Live feature
/// (`strumEngineProvider` is NOT `autoDispose`), and the mini-lesson that
/// follows the Stage restarts the SAME instance on its own mount
/// (`learn_screen.dart` → `liveFrameProvider`) — this class only ever
/// starts/stops it, never disposes it.
class LiveFirstWinEngine implements OnboardingFirstWinEngine {
  LiveFirstWinEngine(this._engine);

  final StrumEngine _engine;
  bool _started = false;

  @override
  Stream<double> get confidence =>
      _engine.frames.map((LiveFrame frame) => frame.confidence);

  @override
  void start() {
    if (_started) return;
    _started = true;
    unawaited(_engine.start());
  }

  @override
  Future<void> stop() async {
    if (!_started) return;
    _started = false;
    await _engine.stop();
  }
}

/// The round's own fake motor (P2) — never reaches a platform channel.
/// Emits nothing until [emit] is called (test/preview control).
class FakeOnboardingFirstWinEngine implements OnboardingFirstWinEngine {
  final _controller = StreamController<double>.broadcast();
  bool _started = false;
  bool _stopped = false;

  @override
  Stream<double> get confidence => _controller.stream;

  @override
  void start() => _started = true;

  /// True once [start] ran and [stop] has not (yet).
  bool get isStarted => _started && !_stopped;

  /// True once [stop] has run — the (simulated) capture is released.
  bool get isStopped => _stopped;

  @override
  Future<void> stop() async {
    _stopped = true;
  }

  /// Test/preview hook: injects one confidence reading, as a real detector
  /// would once the user strums.
  void emit(double value) {
    if (!_controller.isClosed) _controller.add(value);
  }
}
