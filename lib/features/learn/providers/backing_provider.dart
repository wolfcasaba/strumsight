import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../audio/chord_audio.dart';

/// The shared chord-pad player (round 90). One app-wide instance so rapid
/// taps cut the previous pad off instead of stacking; injectable in tests.
final backingProvider = Provider<Backing>((ref) {
  final backing = Backing();
  ref.onDispose(backing.dispose);
  return backing;
});
