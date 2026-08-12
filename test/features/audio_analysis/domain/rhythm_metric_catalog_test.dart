import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/public.dart';

void main() {
  group('rhythm metric catalog (ADR 0233)', () {
    test('target and inferred suites are disjoint', () {
      expect(
        RhythmMetricSuiteIds.target.all.intersection(
          RhythmMetricSuiteIds.inferred.all,
        ),
        isEmpty,
      );
    });

    test('only the target suite contains the measured swing ratio', () {
      expect(
        RhythmMetricSuiteIds.target.all,
        contains(AnalysisMetricId.rhythmTargetSwingRatio),
      );
      expect(
        RhythmMetricSuiteIds.inferred.all,
        isNot(contains(AnalysisMetricId.rhythmTargetSwingRatio)),
      );
    });

    test('all rhythm IDs are registered and use stable versioned names', () {
      final ids = <String>{
        ...RhythmMetricSuiteIds.target.all,
        ...RhythmMetricSuiteIds.inferred.all,
      };
      final pattern = RegExp(r'^[a-z_]+\.[a-z0-9_]+\.v[0-9]+$');
      expect(ids, everyElement(matches(pattern)));
      for (final id in ids) {
        expect(AnalysisMetricId.contains(id), isTrue, reason: id);
      }
    });

    test('the catalog has no accidental collisions', () {
      expect(
        AnalysisMetricId.known.length,
        AnalysisMetricId.known.toSet().length,
      );
    });

    test('metric and localization names do not introduce a style or score', () {
      final forbidden = RegExp(
        r'(swing|shuffle|groove)_?(score|style)',
        caseSensitive: false,
      );
      final strings = <String>[
        ...AnalysisMetricId.known,
        File('lib/l10n/app_en.arb').readAsStringSync(),
        File('lib/l10n/app_hu.arb').readAsStringSync(),
      ];
      for (final value in strings) {
        expect(forbidden.hasMatch(value), isFalse, reason: value);
      }
    });
  });
}
