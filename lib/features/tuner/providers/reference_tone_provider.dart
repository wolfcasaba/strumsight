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
  final AudioPlayer _player = AudioPlayer();

  @override
  Future<void> play(double freqHz) async {
    if (freqHz <= 0) return;
    final wav = ChordAudio.padWav([freqHz], ms: 1500, amp: 0.3);
    try {
      await _player.stop();
      await _player.play(BytesSource(wav));
    } catch (_) {
      // Best-effort, mirrors `Backing._play`.
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (_) {}
  }

  @override
  Future<void> dispose() async {
    try {
      await _player.dispose();
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
