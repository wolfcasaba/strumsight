import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/public.dart';

void main() {
  group('timing metric catalog (ADR 0232)', () {
    test('the pre-existing general timing ID is untouched', () {
      expect(
        AnalysisMetricId.timingMeanAbsoluteError,
        'timing.mean_absolute_error.v1',
      );
      expect(
        AnalysisMetricId.known,
        contains(AnalysisMetricId.timingMeanAbsoluteError),
      );
    });

    test('target and freeplay suites each publish exactly ten IDs', () {
      expect(TimingMetricSuiteIds.target.all, hasLength(10));
      expect(TimingMetricSuiteIds.freeplay.all, hasLength(10));
    });

    test('target and freeplay ID sets are disjoint', () {
      final overlap = TimingMetricSuiteIds.target.all.intersection(
        TimingMetricSuiteIds.freeplay.all,
      );
      expect(overlap, isEmpty);
    });

    test('every new ID matches the stable namespace.name.vN form', () {
      const expression = r'^[a-z_]+\.[a-z0-9_]+\.v[0-9]+$';
      final pattern = RegExp(expression);
      final all = <String>{
        ...TimingMetricSuiteIds.target.all,
        ...TimingMetricSuiteIds.freeplay.all,
      };
      expect(all, everyElement(matches(pattern)));
    });

    test('all new IDs are registered in the closed catalog', () {
      final all = <String>{
        ...TimingMetricSuiteIds.target.all,
        ...TimingMetricSuiteIds.freeplay.all,
      };
      for (final id in all) {
        expect(AnalysisMetricId.contains(id), isTrue, reason: id);
      }
    });

    test('the whole catalog remains unique with no accidental collisions', () {
      expect(
        AnalysisMetricId.known.length,
        equals(AnalysisMetricId.known.toSet().length),
      );
    });
  });
}
