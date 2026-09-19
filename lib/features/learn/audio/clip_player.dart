import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

/// The narrow playback surface the metronome click and the chord pads need.
///
/// A seam, not an abstraction for its own sake: it is the only way a test can
/// inject a player that FAILS and prove the failure reaches the user instead
/// of being swallowed (audit H20 / L12).
abstract interface class ClipPlayer {
  /// Play [wav], cutting off whatever is already sounding. The returned
  /// future completes when the platform accepted the clip, and completes
  /// with an error when it refused it.
  Future<void> play(Uint8List wav);

  /// Release the underlying platform player.
  Future<void> dispose();
}

/// The production [ClipPlayer] — one `audioplayers` player per instance.
///
/// The platform player is created on the FIRST [play], not in the
/// constructor. Constructing an `AudioPlayer` opens the global audioplayers
/// event channel immediately, so merely HOLDING a player — which is what a
/// screen does when it watches the pad's `lastError` to decide whether to
/// render the audio-output notice (audit H20 / L12) — raised a
/// `MissingPluginException` wherever the channel is absent (widget tests,
/// golden recording). Nothing that only looks at the output's health should
/// need a platform channel; only actually playing should.
class AudioPlayersClipPlayer implements ClipPlayer {
  /// A plain player (chord pads, reference tones).
  AudioPlayersClipPlayer() : _lowLatency = false;

  /// A player configured for the metronome click. The config calls are
  /// fire-and-forget — never await a platform round-trip here (it hangs
  /// where the channel is absent, e.g. tests).
  AudioPlayersClipPlayer.lowLatency() : _lowLatency = true;

  final bool _lowLatency;
  AudioPlayer? _player;

  AudioPlayer _ensurePlayer() {
    final existing = _player;
    if (existing != null) return existing;
    final created = AudioPlayer();
    if (_lowLatency) {
      created.setReleaseMode(ReleaseMode.stop).ignore();
      created.setPlayerMode(PlayerMode.lowLatency).ignore();
    }
    return _player = created;
  }

  @override
  Future<void> play(Uint8List wav) {
    final player = _ensurePlayer();
    player.stop().ignore();
    return player.play(BytesSource(wav));
  }

  @override
  Future<void> dispose() async {
    // A player that never played was never created — nothing to release.
    await _player?.dispose();
    _player = null;
  }
}
