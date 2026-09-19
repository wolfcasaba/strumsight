import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../audio/chord_audition.dart';

/// The editor-scoped "hear this chord" player (ADR 0535 D2).
///
/// Autodisposed and meant to be **watched** from the editing screen's
/// `build` so leaving the route drops the last listener and Riverpod tears
/// the player down with it — a chord must never keep ringing on the screen
/// the user navigated to (the tuner reference tone's A5 contract). A bare
/// `ref.read` from a tap callback would create and immediately dispose it.
final chordAuditionProvider = Provider.autoDispose<ChordAudition>((ref) {
  final audition = SynthChordAudition();
  ref.onDispose(audition.dispose);
  return audition;
});
