import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/analyze/model/analyze_result.dart';

import '../../tool/benchmarks/real_audio_dsp_baseline.dart';

void main() {
  group('real-audio DSP baseline metric contract', () {
    test(
      'onset matching uses inclusive integer-microsecond tolerance cells',
      () {
        for (final entry in <(int, int)>[(49999, 1), (50000, 1), (50001, 0)]) {
          final metrics = matchOnsetsUs(
            const [1000000],
            [1000000 + entry.$1],
            toleranceUs: 50000,
          );
          expect(metrics.matched, entry.$2, reason: 'deltaUs=${entry.$1}');
        }
      },
    );

    test('onset matching never reuses one prediction', () {
      final metrics = matchOnsetsUs(
        const [0, 100000],
        const [50000],
        toleranceUs: 50000,
      );

      expect(metrics.matched, 1);
      expect(metrics.falseNegatives, 1);
      expect(metrics.falsePositives, 0);
    });

    test('an uncovered chord event remains an incorrect sample', () {
      final metrics = scoreChords(
        const [GroundTruthEvent(timeUs: 2000000, label: 'C-major')],
        const [TimelineChord(label: 'C', startSec: 0, endSec: 1)],
      );

      expect(metrics.total, 1);
      expect(metrics.correct, 0);
      expect(metrics.perLabel['C-major']!.support, 1);
      expect(metrics.perLabel['C-major']!.recall, 0);
    });

    test(
      'label normalization is exact about quality and accepts pinned enharmonics',
      () {
        final cells = <(String, String, bool)>[
          ('C-major', 'C', true),
          ('Bb-major', 'A#', true),
          ('A-minor', 'Am', true),
          ('C-major', 'Cm', false),
          ('C-major', 'Csus4', false),
          ('A-minor', 'A', false),
        ];

        for (final cell in cells) {
          expect(
            labelsMatch(cell.$1, cell.$2),
            cell.$3,
            reason: '${cell.$1} vs ${cell.$2}',
          );
        }
      },
    );

    test('majority baseline is derived from the supplied distribution', () {
      final baseline = majorityClassBaseline(const [
        'C-major',
        'C-major',
        'C-major',
        'G-major',
        'G-major',
      ]);

      expect(baseline.label, 'C-major');
      expect(baseline.count, 3);
      expect(baseline.total, 5);
      expect(baseline.accuracy, 0.6);
    });

    test('tempo tolerance uses inclusive integer-per-mille boundary cells', () {
      final cells = <(double, int, bool)>[
        (103.9, 39, true),
        (104, 40, true),
        (104.1, 41, false),
      ];

      for (final cell in cells) {
        expect(tempoDeviationPerMille(cell.$1, 100), cell.$2);
        expect(
          temposMatch(cell.$1, 100),
          cell.$3,
          reason: 'predicted=${cell.$1}',
        );
      }
    });

    test('metric-level tempo tolerance accepts only pinned ratios', () {
      final cells = <(double, bool, bool)>[
        (100 / 3, false, true),
        (200 / 3, false, true),
        (100, true, true),
        (200, false, true),
        (50, false, true),
        (150, false, true),
        (300, false, true),
        (137, false, false),
      ];

      for (final cell in cells) {
        expect(temposMatch(cell.$1, 100), cell.$2);
        expect(metricLevelTemposMatch(cell.$1, 100), cell.$3);
      }
    });

    test('missing tempo reference marks the tempo section not run', () {
      final summary = buildTempoSummary(const {'recording_1001': 100}, null);

      expect(summary['status'], 'notRun');
      expect(summary.containsKey('strictTempoMatch'), isFalse);
    });
  });
}
