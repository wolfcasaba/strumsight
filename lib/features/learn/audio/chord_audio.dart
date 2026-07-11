import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

import 'wav.dart';

/// Synthesises a soft chord "pad" in pure Dart and plays it as a jam-mode
/// backing (RAG chunk 014). The chord tones are summed sines with a gentle
/// attack/release — deliberately mellow so it sits under the player. Audio
/// quality is on-device-only to judge; the WAV + chord-tone maths are the
/// unit-tested surface.
class ChordAudio {
  ChordAudio._();

  static const _pitchClass = <String, int>{
    'C': 0, 'C#': 1, 'Db': 1, 'D': 2, 'D#': 3, 'Eb': 3, 'E': 4, 'F': 5,
    'F#': 6, 'Gb': 6, 'G': 7, 'G#': 8, 'Ab': 8, 'A': 9, 'A#': 10, 'Bb': 10,
    'B': 11,
  };

  // Quality suffix → chord-tone semitone offsets from the root.
  static const _quality = <String, List<int>>{
    '': [0, 4, 7],
    'm': [0, 3, 7],
    '7': [0, 4, 7, 10],
    'maj7': [0, 4, 7, 11],
    'm7': [0, 3, 7, 10],
    'sus4': [0, 5, 7],
    'sus2': [0, 2, 7],
    '7sus4': [0, 5, 7, 10],
    'add9': [0, 4, 7, 14],
  };

  /// Chord-tone frequencies (Hz) for [label], voiced around octave 3, or null
  /// if the label can't be parsed.
  static List<double>? frequencies(String label) {
    if (label.isEmpty) return null;
    final rootLen =
        (label.length > 1 && (label[1] == '#' || label[1] == 'b')) ? 2 : 1;
    final pc = _pitchClass[label.substring(0, rootLen)];
    if (pc == null) return null;
    final offsets = _quality[label.substring(rootLen)] ?? const [0, 4, 7];
    final baseMidi = 48 + pc; // around C3
    return [
      for (final o in offsets) 440 * math.pow(2, (baseMidi + o - 69) / 12).toDouble(),
    ];
  }

  /// A soft chord pad WAV for the given [freqs].
  static Uint8List padWav(
    List<double> freqs, {
    int ms = 900,
    int sampleRate = 44100,
    double amp = 0.22,
  }) {
    final n = (sampleRate * ms / 1000).round();
    final samples = Int16List(n);
    final attack = (0.015 * sampleRate).round();
    final release = (0.12 * sampleRate).round();
    final perVoice = amp / math.max(1, freqs.length);
    for (var i = 0; i < n; i++) {
      final t = i / sampleRate;
      // Trapezoidal envelope: gentle attack, sustain, release.
      var env = 1.0;
      if (i < attack) {
        env = i / attack;
      } else if (i > n - release) {
        env = (n - i) / release;
      }
      var s = 0.0;
      for (final f in freqs) {
        s += perVoice * math.sin(2 * math.pi * f * t);
      }
      samples[i] = (s * env * 32767).clamp(-32768.0, 32767.0).toInt();
    }
    return pcmToWav(samples, sampleRate);
  }
}

/// Plays chord pads for jam-mode backing. Fire-and-forget (a no-op where the
/// platform channel is absent, e.g. tests); caches synthesised pads per chord.
class Backing {
  final AudioPlayer _player = AudioPlayer();
  final Map<String, Uint8List> _cache = {};

  Future<void> playChord(String label) async {
    final freqs = ChordAudio.frequencies(label);
    if (freqs == null) return;
    _play(label, () => ChordAudio.padWav(freqs));
  }

  /// A single reference tone (round 94 — tune by ear against the pinned
  /// string). Longer than a chord pad so the ear has time to compare.
  Future<void> playTone(double freqHz) async {
    if (freqHz <= 0) return;
    _play('tone:${freqHz.toStringAsFixed(2)}',
        () => ChordAudio.padWav([freqHz], ms: 1500, amp: 0.3));
  }

  void _play(String cacheKey, Uint8List Function() build) {
    final wav = _cache.putIfAbsent(cacheKey, build);
    try {
      _player.stop().ignore();
      _player.play(BytesSource(wav)).ignore();
    } catch (_) {
      // Best-effort.
    }
  }

  Future<void> dispose() async {
    try {
      await _player.dispose();
    } catch (_) {}
  }
}
