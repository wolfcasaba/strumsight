import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/public.dart';

void main() {
  group('buildGatedPitchMetrics — mandatory suite', () {
    final target = MonophonicPitchTarget(<PitchTargetNote>[
      PitchTargetNote(
        start: Duration.zero,
        end: const Duration(milliseconds: 500),
        midiNote: 69,
      ),
    ]);

    test('registers and publishes exactly the seven required metric IDs', () {
      final report = _report(target: target, cents: 0);
      expect(report.capability.status, CapabilityStatus.available);
      expect(
        report.metrics.map((metric) => metric.id).toSet(),
        PitchMetricIds.all,
      );
      expect(PitchMetricIds.all, hasLength(7));
      for (final id in PitchMetricIds.all) {
        expect(AnalysisMetricId.contains(id), isTrue, reason: id);
      }
    });

    test('intonation threshold is inclusive at +10.00 cents', () {
      // python3 -c 'import math; print(*[440*2**(c/1200) for c in (9.99,10,10.01)])'
      for (final cell in <({double cents, bool expectedHit})>[
        (cents: 9.99, expectedHit: true),
        (cents: 10.00, expectedHit: true),
        (cents: 10.01, expectedHit: false),
      ]) {
        final result = _metric(
          _report(target: target, cents: cell.cents),
          PitchMetricIds.noteHitRatio,
        );
        expect(
          (result.value! as PercentageMetricValue).value,
          cell.expectedHit ? 1 : 0,
        );
      }
    });

    test(
      'disabled or polyphonic capability returns seven non-published metrics',
      () {
        final disabled = buildGatedPitchMetrics(
          analysisPitchEnabled: false,
          target: target,
          frames: _frames(),
          segments: _segments(),
        );
        expect(disabled.capability.status, CapabilityStatus.notApplicable);
        expect(
          disabled.metrics,
          everyElement(
            predicate<AnalysisMetricResult>(
              (metric) => metric.status == CapabilityStatus.notApplicable,
            ),
          ),
        );

        final polyphonic = buildGatedPitchMetrics(
          analysisPitchEnabled: true,
          target: target,
          frames: <PitchFrame>[
            ..._frames(frequency: 110),
            ..._frames(frequency: 440),
          ],
          segments: _segments(),
        );
        expect(
          polyphonic.capability.reason,
          CapabilityUnavailableReason.polyphonicInput,
        );
        expect(
          polyphonic.metrics,
          everyElement(
            predicate<AnalysisMetricResult>(
              (metric) => metric.status == CapabilityStatus.unavailable,
            ),
          ),
        );
      },
    );

    test('English and Hungarian labels cover every pitch metric', () {
      const keys = <String>[
        'pitchMetricNoteHitRatio',
        'pitchMetricMedianCentsError',
        'pitchMetricP90CentsError',
        'pitchMetricStabilityCents',
        'pitchMetricNoteTransitionTiming',
        'pitchMetricSustainedNoteDuration',
        'pitchMetricUnwantedDropoutRatio',
      ];
      final en = File('lib/l10n/app_en.arb').readAsStringSync();
      final hu = File('lib/l10n/app_hu.arb').readAsStringSync();
      for (final key in keys) {
        expect(en, contains('"$key"'), reason: key);
        expect(hu, contains('"$key"'), reason: key);
      }
    });
  });
}

PitchMetricReport _report({
  required MonophonicPitchTarget target,
  required double cents,
}) => buildGatedPitchMetrics(
  analysisPitchEnabled: true,
  target: target,
  frames: _frames(),
  segments: _segments(cents: cents),
);

AnalysisMetricResult _metric(PitchMetricReport report, String id) =>
    report.metrics.firstWhere((metric) => metric.id == id);

List<PitchFrame> _frames({double frequency = 440}) => <PitchFrame>[
  for (var index = 0; index < 10; index += 1)
    PitchFrame(
      time: Duration(milliseconds: index * 50),
      frequencyHz: frequency,
      midiNote: 69,
      confidence: 0.9,
    ),
];

List<MonophonicPitchSegment> _segments({double cents = 0}) {
  final frequency = 440 * math.pow(2, cents / 1200).toDouble();
  return <MonophonicPitchSegment>[
    MonophonicPitchSegment(
      start: Duration.zero,
      end: const Duration(milliseconds: 500),
      medianHz: frequency,
      medianMidi: 69,
      centsOffset: cents,
      stabilityCents: 2,
      confidence: 0.9,
    ),
  ];
}
