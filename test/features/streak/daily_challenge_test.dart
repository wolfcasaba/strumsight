import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/live/model/strum.dart';
import 'package:music_theory/features/streak/daily_challenge.dart';

void main() {
  test('is deterministic — same day yields the same pattern and name', () {
    final a = DailyChallenge.forDay(20000);
    final b = DailyChallenge.forDay(20000);
    expect(a.pattern, b.pattern);
    expect(a.name, b.name);
    expect(a.glyphs, b.glyphs);
  });

  test('different days generally differ', () {
    final patterns = {
      for (var d = 20000; d < 20010; d++) DailyChallenge.forDay(d).glyphs,
    };
    expect(patterns.length, greaterThan(1));
  });

  test('length is always one of 4/6/8 and on-beats are down-strokes', () {
    for (var d = 20000; d < 20050; d++) {
      final c = DailyChallenge.forDay(d);
      expect([4, 6, 8], contains(c.pattern.length));
      for (var i = 0; i < c.pattern.length; i += 2) {
        expect(c.pattern[i], StrumDirection.down,
            reason: 'on-beat $i of day $d should be a down-stroke');
      }
      expect(c.downCount + c.upCount, c.pattern.length);
    }
  });

  test('negative epoch days are handled (seed stays non-negative)', () {
    final c = DailyChallenge.forDay(-5);
    expect(c.pattern, isNotEmpty);
    expect(c.name, isNotEmpty);
  });

  test('glyphs render the ↓/↑ arrows', () {
    final c = DailyChallenge.forDay(20000);
    expect(c.glyphs.replaceAll(' ', '').split(''),
        everyElement(anyOf('↓', '↑')));
  });
}
