import 'dart:async';

/// The first-win mini Stage's confidence source (SDD Ch13 Kör 16, brief §3/
/// P2). Onboarding has no `AudioOwner` variant of its own yet
/// (`lib/core/audio/**` is out of this round's allowed paths), so [start]
/// and [stop] never touch the real microphone this round — a later round
/// wires a production engine once an onboarding-owned audio path exists.
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
