import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/public.dart';

void main() {
  group('detectLocalAccents — moving-median accent detection (OD-02)', () {
    test('a single loud stroke among flat neighbours is the only accent', () {
      final strengths = List<double>.filled(15, 1.0);
      strengths[7] = 2.0;
      final events = _events(strengths);

      final result = detectLocalAccents(events: events);

      expect(result.accentEventIds, <String>{'e7'});
      expect(result.localRatioByEventId['e7'], closeTo(2.0, 1e-9));
      expect(result.localRatioByEventId['e6'], closeTo(1.0, 1e-9));
    });

    test('no accent below the threshold ratio', () {
      final strengths = List<double>.filled(15, 1.0);
      strengths[7] = 1.19;
      final events = _events(strengths);

      final result = detectLocalAccents(events: events);

      expect(result.accentEventIds, isEmpty);
    });

    test(
      'accent locality: a gradual global ramp is not a true accent, but the '
      'session-median variant of the same fixture falsely reports several',
      () {
        // python3 -c (see docs/rag/chunks/022-dynamics-stroke-balance.md):
        // linear ramp 1.0..2.0 over 41 events; local (radius=4) max ratio
        // ~1.026 (< 1.2, no accent); global (radius=events.length) max ratio
        // ~1.333 with 8 events above the 1.2 threshold.
        const n = 41;
        final strengths = <double>[
          for (var index = 0; index < n; index++) 1.0 + index / (n - 1),
        ];
        final events = _events(strengths);

        final local = detectLocalAccents(events: events);
        final sessionWide = detectLocalAccents(
          events: events,
          windowRadius: events.length,
        );

        expect(
          local.accentEventIds,
          isEmpty,
          reason: 'the local window must track the gradual ramp',
        );
        expect(sessionWide.accentEventIds, isNotEmpty);
        expect(local.accentEventIds, isNot(sessionWide.accentEventIds));
      },
    );

    test('edge windows truncate instead of wrapping or throwing', () {
      final strengths = <double>[3.0, 1.0, 1.0, 1.0, 1.0, 1.0];
      final events = _events(strengths);

      final result = detectLocalAccents(events: events);

      expect(result.accentEventIds, <String>{'e0'});
    });

    test('rejects a threshold ratio at or below one', () {
      expect(
        () => detectLocalAccents(
          events: _events(<double>[1, 1]),
          thresholdRatio: 1,
        ),
        throwsArgumentError,
      );
    });

    test('rejects a non-positive window radius', () {
      expect(
        () => detectLocalAccents(
          events: _events(<double>[1, 1]),
          windowRadius: 0,
        ),
        throwsArgumentError,
      );
    });
  });
}

List<StrumEvent> _events(List<double> strengths) => <StrumEvent>[
  for (var index = 0; index < strengths.length; index++)
    StrumEvent(
      id: 'e$index',
      time: Duration(milliseconds: 200 * index),
      confidence: 1.0,
      direction: StrumDirection.down,
      sampleIndex: index * 1000,
      attackStrength: strengths[index],
      localRms: strengths[index] * 0.5,
    ),
];
