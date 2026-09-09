import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../../../core/audio/synth/plucked_string_synth.dart';
import '../../../core/music/chord_voicing.dart';
import '../../../core/music/strum.dart';
import '../../chords/public.dart';
import 'chord_audio.dart';

/// Where an audition's pitches came from (ADR 0535 D1).
enum AuditionSource {
  /// The library fingering: every sounding string of the diagram.
  fingering,

  /// No diagram for this label — the parsed chord tones around C3 instead.
  chordTones,

  /// The label could not be parsed at all; nothing plays.
  none,
}

/// The resolved pitches of one audition, low → high.
@immutable
final class AuditionVoicing {
  const AuditionVoicing({required this.freqs, required this.source});

  const AuditionVoicing.none() : freqs = const [], source = AuditionSource.none;

  final List<double> freqs;
  final AuditionSource source;

  bool get isPlayable => freqs.isNotEmpty;
}

/// "Hear what I just tapped" for the song editors (ADR 0535).
///
/// Distinct from [Backing]: that is the app-wide jam-mode pad (soft sines on
/// every downbeat, shared so rapid taps cut each other off). Audition is
/// route-scoped (one per editor, torn down with it) and plays the real
/// fingering as a strummed, plucked-string chord — the sound the user will
/// make on the guitar, so composing by ear in the editor is honest.
abstract class ChordAudition {
  /// Play [label] once as a single stroke in [direction].
  Future<void> strum(
    String label, {
    StrumDirection direction = StrumDirection.down,
  });

  Future<void> stop();

  Future<void> dispose();
}

/// The playback seam under [SynthChordAudition]: how a synthesised WAV
/// reaches the speaker. Injectable so the resolution + caching logic is
/// unit-testable without a platform channel.
abstract class WavPlayback {
  Future<void> play(Uint8List wav);
  Future<void> stop();
  Future<void> dispose();
}

/// `audioplayers`-backed [WavPlayback]. Lazy: the `AudioPlayer` touches a
/// platform channel on construction, so it is created on the first stroke,
/// never on provider/screen build (the tuner reference tone's lesson).
final class AudioPlayersWavPlayback implements WavPlayback {
  AudioPlayer? _player;
  AudioPlayer get _playerOrCreate => _player ??= AudioPlayer();

  @override
  Future<void> play(Uint8List wav) async {
    try {
      await _playerOrCreate.stop();
      await _playerOrCreate.play(BytesSource(wav));
    } catch (_) {
      // Best-effort, like `Backing._play`: a missing platform channel (tests,
      // desktop without audio) must not break editing.
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _player?.stop();
    } catch (_) {
      // Best-effort; see `play`.
    }
  }

  @override
  Future<void> dispose() async {
    await stop();
    try {
      await _player?.dispose();
    } catch (_) {
      // Best-effort; see `play`.
    }
    _player = null;
  }
}

/// Resolves a label to its fingering and strums it with the plucked-string
/// synth. Rendered strokes are cached (LRU, bounded like `Backing`) — a
/// 1.6 s chord at 44.1 kHz is ~140 KB, and an editor session taps the same
/// handful of chords over and over.
final class SynthChordAudition implements ChordAudition {
  SynthChordAudition({WavPlayback? playback})
    : _playback = playback ?? AudioPlayersWavPlayback();

  /// Beyond this the least-recently-used stroke is evicted.
  static const int maxCachedStrokes = 24;

  final WavPlayback _playback;
  final Map<String, Uint8List> _cache = {};

  /// Current number of cached strokes (test surface for the bound).
  int get cacheSize => _cache.length;

  /// Cached keys oldest → newest (test surface — proves a HIT refreshes
  /// recency, the `Backing.debugCacheKeys` precedent).
  @visibleForTesting
  List<String> get debugCacheKeys => List.unmodifiable(_cache.keys);

  /// What [label] would sound as. Pure — the unit-tested contract:
  /// fingering first, chord tones as the fallback, nothing for junk.
  static AuditionVoicing resolve(String label, {int a4 = 440}) {
    final shape = ChordShapes.forLabel(label);
    if (shape != null) {
      final freqs = ChordVoicing.frequencies(shape.frets, a4: a4);
      if (freqs.isNotEmpty) {
        return AuditionVoicing(freqs: freqs, source: AuditionSource.fingering);
      }
    }
    // An unknown quality suffix ("Cdim", "C5") must NOT sound as a major
    // triad — that would be a confidently wrong answer to the composer.
    if (!ChordAudio.hasKnownQuality(label)) return const AuditionVoicing.none();
    final tones = ChordAudio.frequencies(label);
    if (tones == null || tones.isEmpty) return const AuditionVoicing.none();
    return AuditionVoicing(freqs: tones, source: AuditionSource.chordTones);
  }

  @override
  Future<void> strum(
    String label, {
    StrumDirection direction = StrumDirection.down,
  }) async {
    final voicing = resolve(label);
    if (!voicing.isPlayable) return;
    final key = '$label:${direction.name}';
    // LRU: re-insert on hit so the map's iteration order is recency.
    final wav =
        _cache.remove(key) ??
        PluckedStringSynth.strumWav(
          freqs: voicing.freqs,
          downstroke: direction == StrumDirection.down,
        );
    _cache[key] = wav;
    if (_cache.length > maxCachedStrokes) _cache.remove(_cache.keys.first);
    await _playback.play(wav);
  }

  @override
  Future<void> stop() => _playback.stop();

  @override
  Future<void> dispose() async {
    _cache.clear();
    await _playback.dispose();
  }
}
