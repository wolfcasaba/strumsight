import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

import 'wav.dart';

/// A play-along metronome. The click is **synthesised in pure Dart** (a short
/// decaying sine → a valid 16-bit PCM WAV) so there is no bundled asset and the
/// generator is unit-testable; playback goes through the existing `audioplayers`
/// dep. All playback is best-effort (a no-op where the platform channel is
/// absent, e.g. tests). RAG chunk 014.
class Metronome {
  Metronome()
      : _click = buildClickWav(freq: 1000, amp: 0.5),
        _accent = buildClickWav(freq: 1600, amp: 0.7);

  final Uint8List _click;
  final Uint8List _accent;
  AudioPlayer? _player;

  void _ensurePlayer() {
    if (_player != null) return;
    try {
      final p = AudioPlayer();
      // Fire-and-forget config — never await a platform round-trip (it hangs
      // where the channel is absent, e.g. tests).
      p.setReleaseMode(ReleaseMode.stop).ignore();
      p.setPlayerMode(PlayerMode.lowLatency).ignore();
      _player = p;
    } catch (_) {
      // No audio available — clicks become no-ops.
    }
  }

  /// Play one tick; [accent] uses the higher-pitched downbeat click. Returns
  /// immediately — playback is fire-and-forget so a click can never stall or
  /// disrupt the lesson clock.
  Future<void> tick({bool accent = false}) async {
    try {
      _ensurePlayer();
      final p = _player;
      if (p == null) return;
      final src = BytesSource(accent ? _accent : _click);
      p.stop().ignore();
      p.play(src).ignore();
    } catch (_) {
      // Best-effort.
    }
  }

  Future<void> dispose() async {
    try {
      await _player?.dispose();
    } catch (_) {}
    _player = null;
  }

  /// Build a mono 16-bit PCM WAV of a short decaying-sine click. Pure &
  /// deterministic — the returned bytes start with the `RIFF`/`WAVE` header.
  static Uint8List buildClickWav({
    double freq = 1000,
    int ms = 35,
    int sampleRate = 44100,
    double amp = 0.5,
    double decayPerSec = 70,
  }) {
    final n = (sampleRate * ms / 1000).round();
    final samples = Int16List(n);
    for (var i = 0; i < n; i++) {
      final t = i / sampleRate;
      final env = math.exp(-decayPerSec * t);
      final s = amp * env * math.sin(2 * math.pi * freq * t);
      samples[i] = (s * 32767).clamp(-32768.0, 32767.0).toInt();
    }
    return pcmToWav(samples, sampleRate);
  }
}
