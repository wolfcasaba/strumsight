import 'dart:math' as math;

import '../live/model/strum.dart';

/// A daily strum-pattern challenge, derived **deterministically** from the
/// epoch day so every device shows the same pattern on the same date with no
/// server (RAG chunk 013 — the daily hook that gives the streak something
/// concrete to play). Pure and reproducible.
class DailyChallenge {
  const DailyChallenge({
    required this.day,
    required this.name,
    required this.pattern,
  });

  /// Epoch day this challenge is for.
  final int day;

  /// A fun, human name for the pattern (rotates by day).
  final String name;

  /// The target strokes, in order.
  final List<StrumDirection> pattern;

  int get downCount =>
      pattern.where((d) => d == StrumDirection.down).length;
  int get upCount => pattern.length - downCount;

  static const _names = [
    'Campfire', 'Backbeat Bounce', 'Island Groove', 'Folk Shuffle',
    'Pop Punk Push', 'Country Roll', 'Reggae Skank', 'Ballad Sway',
    'Funk Chop', 'Train Beat', 'Waltz Lilt', 'Anthem Drive',
  ];

  /// The challenge for [epochDay]. On-beats are down-strokes; off-beats vary,
  /// so the patterns stay musical while differing day to day.
  factory DailyChallenge.forDay(int epochDay) {
    // Non-negative, day-stable seed.
    final rng = math.Random(epochDay & 0x7fffffff);
    final length = const [4, 6, 8][rng.nextInt(3)];
    final pattern = <StrumDirection>[];
    for (var i = 0; i < length; i++) {
      final onBeat = i.isEven;
      final up = !onBeat && rng.nextDouble() < 0.7; // off-beats mostly up
      pattern.add(up ? StrumDirection.up : StrumDirection.down);
    }
    final name = _names[(epochDay % _names.length + _names.length) %
        _names.length];
    return DailyChallenge(day: epochDay, name: name, pattern: pattern);
  }

  /// The pattern as arrow glyphs, e.g. "↓ ↑ ↓ ↑".
  String get glyphs =>
      pattern.map((d) => d == StrumDirection.down ? '↓' : '↑').join(' ');
}
