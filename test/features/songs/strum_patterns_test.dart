import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/live/model/strum.dart';
import 'package:music_theory/features/songs/theory/strum_patterns.dart';

void main() {
  test('every preset is exactly 8 slots with at least one stroke', () {
    for (final p in StrumPatternPreset.all) {
      expect(p.pattern.length, 8, reason: '${p.name} must be 8 slots');
      expect(p.pattern.any((d) => d != null), isTrue,
          reason: '${p.name} must have a stroke');
    }
  });

  test('Down is four quarter-note downstrokes', () {
    final down = StrumPatternPreset.all.firstWhere((p) => p.name == 'Down');
    expect(down.pattern.where((d) => d == StrumDirection.down).length, 4);
    expect(down.pattern.where((d) => d == StrumDirection.up).length, 0);
  });

  test('Eighths is eight alternating down/up strokes', () {
    final eighths =
        StrumPatternPreset.all.firstWhere((p) => p.name == 'Eighths');
    expect(eighths.pattern.every((d) => d != null), isTrue);
    expect(eighths.pattern.where((d) => d == StrumDirection.up).length, 4);
  });

  test('Reggae is off-beat up-strokes only', () {
    final reggae = StrumPatternPreset.all.firstWhere((p) => p.name == 'Reggae');
    expect(reggae.pattern.where((d) => d == StrumDirection.down).length, 0);
    expect(reggae.pattern.where((d) => d == StrumDirection.up).length, 4);
    // Strokes land on the off-beats (odd slots).
    for (var i = 0; i < 8; i += 2) {
      expect(reggae.pattern[i], isNull);
    }
  });
}
