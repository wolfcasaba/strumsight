import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice/domain/model/practice_metrics.dart';

void main() {
  group('MetricValue validation', () {
    test(
      'accepts available score boundaries and explicit unavailable states',
      () {
        expect(const MetricAvailable(0).validate(), isEmpty);
        expect(const MetricAvailable(1).validate(), isEmpty);
        expect(const MetricNotApplicable().validate(), isEmpty);
        expect(const MetricInsufficientData('lowSignal').validate(), isEmpty);
      },
    );

    test('reports non-finite values without a duplicate range failure', () {
      for (final value in [
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        expect(
          MetricAvailable(value).validate().map((failure) => failure.code),
          ['metric.value.notFinite'],
        );
      }
    });

    test('rejects finite values outside zero through one', () {
      for (final value in [-0.01, 1.01]) {
        expect(
          MetricAvailable(value).validate().map((failure) => failure.code),
          contains('metric.value.outOfRange'),
        );
      }
    });

    test('requires an insufficient-data reason code', () {
      expect(
        const MetricInsufficientData(
          '',
        ).validate().map((failure) => failure.code),
        contains('metric.insufficientData.reasonEmpty'),
      );
    });
  });

  group('PracticeMetrics validation', () {
    test('accepts a valid metric set including signed timing bias', () {
      expect(
        _metrics(timingBias: const Duration(milliseconds: -5)).validate(),
        isEmpty,
      );
    });

    test('passes nested metric failures through unchanged', () {
      expect(
        _metrics(
          completion: const MetricAvailable(double.infinity),
        ).validate().map((failure) => failure.code),
        contains('metric.value.notFinite'),
      );
    });

    test('rejects negative total target count', () {
      expect(
        _metrics(
          totalTargets: -1,
          resolvedTargets: 0,
        ).validate().map((failure) => failure.code),
        contains('metrics.totalTargets.negative'),
      );
    });

    test('rejects resolved targets greater than total targets', () {
      expect(
        _metrics(
          totalTargets: 1,
          resolvedTargets: 2,
        ).validate().map((failure) => failure.code),
        contains('metrics.resolvedTargets.exceedsTotal'),
      );
    });

    test('rejects negative max combo and score points', () {
      final codes = _metrics(
        maxCombo: -1,
        scorePoints: -1,
      ).validate().map((failure) => failure.code);

      expect(
        codes,
        containsAll({
          'metrics.maxCombo.negative',
          'metrics.scorePoints.negative',
        }),
      );
    });

    test('rejects a negative mean absolute offset', () {
      expect(
        _metrics(
          meanAbsoluteOffset: const Duration(microseconds: -1),
        ).validate().map((failure) => failure.code),
        contains('metrics.meanAbsoluteOffset.negative'),
      );
    });
  });

  group('Practice metric value semantics', () {
    test('compares every MetricValue subtype by structure and subtype', () {
      final available = MetricAvailable(0.8);
      final sameAvailable = MetricAvailable(0.8);
      final insufficient = MetricInsufficientData('lowSignal');
      final sameInsufficient = MetricInsufficientData('lowSignal');
      final notApplicable = MetricNotApplicable();
      final sameNotApplicable = MetricNotApplicable();

      expect(identical(available, sameAvailable), isFalse);
      expect(available, sameAvailable);
      expect(available.hashCode, sameAvailable.hashCode);
      expect(available, isNot(const MetricAvailable(0.7)));
      expect(identical(insufficient, sameInsufficient), isFalse);
      expect(insufficient, sameInsufficient);
      expect(insufficient.hashCode, sameInsufficient.hashCode);
      expect(
        insufficient,
        isNot(const MetricInsufficientData('tooFewTargets')),
      );
      expect(identical(notApplicable, sameNotApplicable), isFalse);
      expect(notApplicable, sameNotApplicable);
      expect(notApplicable.hashCode, sameNotApplicable.hashCode);
      expect(notApplicable, isNot(available));
    });

    test('compares PracticeMetrics structurally', () {
      final metrics = _metrics();
      final sameValue = _metrics();
      final different = _metrics(scorePoints: 101);

      expect(metrics, sameValue);
      expect(metrics.hashCode, sameValue.hashCode);
      expect(metrics, isNot(different));
    });
  });
}

PracticeMetrics _metrics({
  MetricValue completion = const MetricAvailable(1),
  MetricValue rhythm = const MetricAvailable(0.8),
  MetricValue direction = const MetricNotApplicable(),
  MetricValue chord = const MetricInsufficientData('tooFewTargets'),
  MetricValue overall = const MetricAvailable(0.8),
  int totalTargets = 10,
  int resolvedTargets = 8,
  int maxCombo = 4,
  int scorePoints = 100,
  Duration meanAbsoluteOffset = const Duration(milliseconds: 20),
  Duration timingBias = const Duration(milliseconds: 5),
}) => PracticeMetrics(
  completion: completion,
  rhythm: rhythm,
  direction: direction,
  chord: chord,
  overall: overall,
  totalTargets: totalTargets,
  resolvedTargets: resolvedTargets,
  maxCombo: maxCombo,
  scorePoints: scorePoints,
  meanAbsoluteOffset: meanAbsoluteOffset,
  timingBias: timingBias,
);
