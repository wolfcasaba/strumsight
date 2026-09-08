import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../../../core/audio/codec/wav_encoder.dart';
import 'audio_playback_error.dart';
import 'clip_player.dart';

/// A play-along metronome. The click is **synthesised in pure Dart** (a short
/// decaying sine → a valid 16-bit PCM WAV) so there is no bundled asset and the
/// generator is unit-testable; playback goes through the existing `audioplayers`
/// dep behind the [ClipPlayer] seam. Playback stays fire-and-forget (a no-op
/// where the platform channel is absent, e.g. tests) but it is no longer
/// SILENT: a refused click lands in [lastError] so the screen can tell the
/// player the metronome is running without a sound (audit H20 / L12).
/// RAG chunk 014.
class Metronome {
  Metronome({ClipPlayer Function()? playerFactory})
    : _newPlayer = playerFactory ?? AudioPlayersClipPlayer.lowLatency,
      _click = buildClickWav(freq: 1000, amp: 0.5),
      _accent = buildClickWav(freq: 1600, amp: 0.7);

  final ClipPlayer Function() _newPlayer;
  final Uint8List _click;
  final Uint8List _accent;
  final ValueNotifier<AudioPlaybackError?> _lastError = ValueNotifier(null);
  ClipPlayer? _player;
  bool _disposed = false;

  /// The click the device refused to play, or null while the output is
  /// healthy. A silent metronome must never look like a running one, so the
  /// metronome/lesson screens render a localized message from this.
  ValueListenable<AudioPlaybackError?> get lastError => _lastError;

  /// Drop the surfaced error (the player dismissed it or restarted).
  void clearError() {
    if (!_disposed) _lastError.value = null;
  }

  void _ensurePlayer() {
    if (_player != null) return;
    try {
      _player = _newPlayer();
    } catch (error) {
      // No audio available — clicks become no-ops, but not silent ones.
      _report(error);
    }
  }

  void _report(Object error) {
    if (_disposed || isAudioBackendAbsent(error)) return;
    _lastError.value = AudioPlaybackError(
      source: AudioOutputSource.metronomeClick,
      detail: error.toString(),
    );
  }

  /// Play one tick; [accent] uses the higher-pitched downbeat click. Returns
  /// immediately — playback is fire-and-forget so a click can never stall or
  /// disrupt the lesson clock. A refused clip is reported through
  /// [lastError] rather than swallowed.
  Future<void> tick({bool accent = false}) async {
    try {
      _ensurePlayer();
      final p = _player;
      if (p == null) return;
      final clip = accent ? _accent : _click;
      p.play(clip).onError<Object>((e, _) => _report(e)).ignore();
    } catch (error) {
      _report(error);
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    try {
      await _player?.dispose();
    } catch (_) {
      // Nothing left to surface — the metronome is going away.
    }
    _player = null;
    _lastError.dispose();
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
