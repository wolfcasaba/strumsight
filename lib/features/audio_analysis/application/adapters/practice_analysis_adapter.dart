import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/features/practice/public.dart';

import '../../domain/analysis_document.dart';
import '../../domain/analysis_event.dart' show StrumDirection;
import '../../domain/analysis_metric.dart';
import '../../domain/target/analysis_target.dart';
import '../../domain/target/expected_event.dart';

/// Named severity boundaries for the conservative retry-tempo policy.
abstract final class PracticeRetryTempoPolicy {
  static const double noReductionThrough = 0.25;
  static const double gentleReductionThrough = 0.5;
  static const double moderateReductionThrough = 0.75;
  static const double gentleReduction = 0.05;
  static const double moderateReduction = 0.10;
  static const double strongReduction = 0.15;
  static const double minimumTargetFraction = 0.60;
}

/// A stable fact for Practice UI or policy consumers, never a session score.
final class PracticeAnalysisFact {
  const PracticeAnalysisFact({
    required this.metricId,
    required this.confidence,
    required this.value,
  });

  final String metricId;
  final double confidence;
  final Object? value;
}

/// A bounded action Practice can associate with an analysis hotspot.
final class PracticeAnalysisHotspotAction {
  const PracticeAnalysisHotspotAction({
    required this.hotspotId,
    required this.start,
    required this.end,
  });

  final String hotspotId;
  final Duration start;
  final Duration end;
}

/// Analysis evidence that supplements, but never replaces, Practice scoring.
final class PracticeAnalysisEvidence {
  PracticeAnalysisEvidence({
    required List<PracticeAnalysisFact> facts,
    required List<PracticeAnalysisHotspotAction> hotspots,
    required this.recommendedRetryTempo,
    required this.completionEligibility,
  }) : facts = List<PracticeAnalysisFact>.unmodifiable(facts),
       hotspots = List<PracticeAnalysisHotspotAction>.unmodifiable(hotspots);

  final List<PracticeAnalysisFact> facts;
  final List<PracticeAnalysisHotspotAction> hotspots;
  final double recommendedRetryTempo;
  final bool completionEligibility;
}

/// Converts the public Practice snapshot to target facts owned by Analysis.
final class PracticeAnalysisAdapter {
  const PracticeAnalysisAdapter();

  AnalysisTarget toAnalysisTarget(CompiledPracticeTarget compiled) {
    final expectedEvents = <ExpectedEvent>[];
    for (final event in compiled.events) {
      final type = event.direction != null
          ? ExpectedEventType.strum
          : event.chord != null
          ? ExpectedEventType.chordChange
          : ExpectedEventType.onset;
      expectedEvents.add(
        ExpectedEvent(
          id: 'practice:${event.sourceEventId}:${event.loopIndex}',
          time: event.time,
          type: type,
          direction: event.direction == null
              ? null
              : StrumDirection.values.byName(event.direction!.name),
        ),
      );
    }

    return AnalysisTarget(
      id: compiled.definitionId,
      targetVersion: compiled.definitionSnapshotVersion,
      kind: AnalysisTargetKind.practice,
      timebase: AnalysisTargetTimebase.session,
      expectedEvents: expectedEvents,
      expectedChords: <String>{
        for (final segment in compiled.expectedChordSegments) segment.chord,
      }.toList(growable: false),
      sections: <AnalysisTargetSection>[
        for (final (index, segment) in compiled.expectedChordSegments.indexed)
          AnalysisTargetSection(
            id: 'practice-chord-$index',
            start: segment.start,
            end: segment.end,
          ),
      ],
    );
  }

  PracticeAnalysisEvidence evidenceFor({
    required AnalysisDocument document,
    required double targetTempo,
    required double timingErrorSeverity,
  }) {
    if (!targetTempo.isFinite || targetTempo <= 0) {
      throw ArgumentError.value(targetTempo, 'targetTempo');
    }
    if (!timingErrorSeverity.isFinite ||
        timingErrorSeverity < 0 ||
        timingErrorSeverity > 1) {
      throw ArgumentError.value(timingErrorSeverity, 'timingErrorSeverity');
    }

    return PracticeAnalysisEvidence(
      facts: <PracticeAnalysisFact>[
        for (final metric in document.metrics)
          PracticeAnalysisFact(
            metricId: metric.id,
            confidence: metric.confidence,
            value: _metricValue(metric.value),
          ),
      ],
      hotspots: <PracticeAnalysisHotspotAction>[
        for (final hotspot in document.hotspots)
          PracticeAnalysisHotspotAction(
            hotspotId: hotspot.id,
            start: hotspot.start,
            end: hotspot.end,
          ),
      ],
      recommendedRetryTempo: recommendedRetryTempo(
        targetTempo: targetTempo,
        timingErrorSeverity: timingErrorSeverity,
      ),
      completionEligibility:
          document.completion.status == AnalysisCompletionStatus.complete,
    );
  }

  double recommendedRetryTempo({
    required double targetTempo,
    required double timingErrorSeverity,
  }) {
    final reduction = switch (timingErrorSeverity) {
      <= PracticeRetryTempoPolicy.noReductionThrough => 0.0,
      <= PracticeRetryTempoPolicy.gentleReductionThrough =>
        PracticeRetryTempoPolicy.gentleReduction,
      <= PracticeRetryTempoPolicy.moderateReductionThrough =>
        PracticeRetryTempoPolicy.moderateReduction,
      _ => PracticeRetryTempoPolicy.strongReduction,
    };
    return (targetTempo * (1 - reduction)).clamp(
      targetTempo * PracticeRetryTempoPolicy.minimumTargetFraction,
      double.infinity,
    );
  }
}

Object? _metricValue(AnalysisMetricValue? value) => switch (value) {
  ScalarMetricValue(:final value) => value,
  PercentageMetricValue(:final value) => value,
  DurationMetricValue(:final value) => value.inMicroseconds,
  DistributionMetricValue(:final values) => List<double>.unmodifiable(values),
  TimeSeriesMetricValue(:final points) => List<Object>.unmodifiable(
    points.map((point) => <Object>[point.time.inMicroseconds, point.value]),
  ),
  CategoryMetricValue(:final value) => value,
  ScoreMetricValue(:final value) => value,
  null => null,
};

abstract interface class PracticeAnalysisAdapterFactory {
  PracticeAnalysisAdapter create();
}

final class _DefaultPracticeAnalysisAdapterFactory
    implements PracticeAnalysisAdapterFactory {
  const _DefaultPracticeAnalysisAdapterFactory();

  @override
  PracticeAnalysisAdapter create() => const PracticeAnalysisAdapter();
}

final practiceAnalysisAdapterFactoryProvider =
    Provider<PracticeAnalysisAdapterFactory>(
      (_) => const _DefaultPracticeAnalysisAdapterFactory(),
    );

/// Null while the OFF-by-default Practice integration is unavailable.
final practiceAnalysisAdapterProvider = Provider<PracticeAnalysisAdapter?>((
  ref,
) {
  if (!ref.watch(appConfigProvider).flags.analysisPracticeIntegrationEnabled) {
    return null;
  }
  return ref.watch(practiceAnalysisAdapterFactoryProvider).create();
});
