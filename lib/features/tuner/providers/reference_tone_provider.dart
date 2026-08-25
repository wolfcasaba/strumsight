import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../learn/public.dart' show ChordAudio;

/// Plays the "tune by ear" reference tone (round 94) and can be told to
/// stop. Tuner-owned (unlike the shared, app-wide `Backing` in
/// `features/learn/`) so it can be tied to the Tuner route's own lifetime —
/// the shared `Backing` instance is never disposed on a single screen leaving
/// (other features keep using it), which is exactly the "still audible after
/// leaving" risk the round brief names (§9, A5).
abstract class ReferenceTonePlayer {
  Future<void> play(double freqHz);
  Future<void> stop();
  Future<void> dispose();
}

class RealReferenceTonePlayer implements ReferenceTonePlayer {
  // Lazy: the provider is watched (and this class constructed) on every
  // Tuner build, but most visits never tap the reference-tone button —
  // `AudioPlayer()` touches a platform channel on construction, so building
  // it eagerly here would reach that channel on every Tuner mount, including
  // widget/golden tests that never override this provider.
  AudioPlayer? _player;
  AudioPlayer get _playerOrCreate => _player ??= AudioPlayer();

  @override
  Future<void> play(double freqHz) async {
    if (freqHz <= 0) return;
    final wav = ChordAudio.padWav([freqHz], ms: 1500, amp: 0.3);
    try {
      await _playerOrCreate.stop();
      await _playerOrCreate.play(BytesSource(wav));
    } catch (_) {
      // Best-effort, mirrors `Backing._play`.
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _player?.stop();
    } catch (_) {}
  }

  @override
  Future<void> dispose() async {
    await stop();
    try {
      await _player?.dispose();
    } catch (_) {}
  }
}

/// Autodisposed and watched from the Tuner screen's `build` (not merely
/// `read`) so leaving the route drops the last listener and Riverpod tears
/// the player — and with it the reference tone and its audio focus — down
/// (A5).
final referenceTonePlayerProvider = Provider.autoDispose<ReferenceTonePlayer>((
  ref,
) {
  final player = RealReferenceTonePlayer();
  ref.onDispose(player.dispose);
  return player;
});
