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
class AudioPlayersClipPlayer implements ClipPlayer {
  /// A plain player (chord pads, reference tones).
  AudioPlayersClipPlayer() : _player = AudioPlayer();

  /// A player configured for the metronome click. The config calls are
  /// fire-and-forget — never await a platform round-trip here (it hangs
  /// where the channel is absent, e.g. tests).
  AudioPlayersClipPlayer.lowLatency() : _player = AudioPlayer() {
    _player.setReleaseMode(ReleaseMode.stop).ignore();
    _player.setPlayerMode(PlayerMode.lowLatency).ignore();
  }

  final AudioPlayer _player;

  @override
  Future<void> play(Uint8List wav) {
    _player.stop().ignore();
    return _player.play(BytesSource(wav));
  }

  @override
  Future<void> dispose() => _player.dispose();
}
