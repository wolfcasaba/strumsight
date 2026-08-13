import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:strumsight/app/config/app_config.dart';

import '../../domain/analysis_document.dart';
import '../../domain/analysis_event.dart';
import '../../domain/analysis_metric.dart';
import '../../domain/target/analysis_target.dart';

/// Explicitly forbidden key names for the compact Tutor boundary.
abstract final class TutorSnapshotRedaction {
  static const Set<String> forbiddenKeys = <String>{
    'pcm',
    'waveform',
    'fileName',
    'filename',
    'deviceId',
    'deviceIdentifier',
    'analysisDocument',
  };
  static const int maxEvents = 50;
}

final class TutorMetricFact {
  const TutorMetricFact({
    required this.id,
    required this.confidence,
    required this.value,
  });
  final String id;
  final double confidence;
  final Object? value;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'confidence': confidence,
    'value': value,
  };
}

final class TutorHotspotRange {
  const TutorHotspotRange({
    required this.id,
    required this.startMicroseconds,
    required this.endMicroseconds,
    required this.confidence,
  });
  final String id;
  final int startMicroseconds;
  final int endMicroseconds;
  final double confidence;

  Map<String, Object> toJson() => <String, Object>{
    'id': id,
    'startMicroseconds': startMicroseconds,
    'endMicroseconds': endMicroseconds,
    'confidence': confidence,
  };
}

final class TutorEventFact {
  const TutorEventFact({
    required this.id,
    required this.timeMicroseconds,
    required this.confidence,
    required this.kind,
  });
  final String id;
  final int timeMicroseconds;
  final double confidence;
  final String kind;

  Map<String, Object> toJson() => <String, Object>{
    'id': id,
    'timeMicroseconds': timeMicroseconds,
    'confidence': confidence,
    'kind': kind,
  };
}

final class TutorTargetContext {
  const TutorTargetContext({
    required this.id,
    required this.version,
    required this.kind,
    required this.expectedEventCount,
  });
  final String id;
  final int version;
  final String kind;
  final int expectedEventCount;

  factory TutorTargetContext.fromTarget(AnalysisTarget target) =>
      TutorTargetContext(
        id: target.id,
        version: target.targetVersion,
        kind: target.kind.name,
        expectedEventCount: target.expectedEvents.length,
      );

  Map<String, Object> toJson() => <String, Object>{
    'id': id,
    'version': version,
    'kind': kind,
    'expectedEventCount': expectedEventCount,
  };
}

/// Immutable, redacted facts the Tutor may consume in a future Tutor round.
final class TutorAnalysisSnapshot {
  TutorAnalysisSnapshot({
    required List<String> insightIds,
    required List<TutorMetricFact> metricFacts,
    required List<TutorHotspotRange> hotspots,
    required List<TutorEventFact> events,
    this.targetContext,
  }) : insightIds = List<String>.unmodifiable(insightIds),
       metricFacts = List<TutorMetricFact>.unmodifiable(metricFacts),
       hotspots = List<TutorHotspotRange>.unmodifiable(hotspots),
       events = List<TutorEventFact>.unmodifiable(events) {
    if (this.events.length > TutorSnapshotRedaction.maxEvents) {
      throw ArgumentError.value(events, 'events', 'exceeds hard redaction cap');
    }
  }

  final List<String> insightIds;
  final List<TutorMetricFact> metricFacts;
  final List<TutorHotspotRange> hotspots;
  final List<TutorEventFact> events;
  final TutorTargetContext? targetContext;

  Map<String, Object?> toJson() => <String, Object?>{
    'insightIds': insightIds,
    'metricFacts': metricFacts.map((fact) => fact.toJson()).toList(),
    'hotspots': hotspots.map((hotspot) => hotspot.toJson()).toList(),
    'events': events.map((event) => event.toJson()).toList(),
    if (targetContext != null) 'targetContext': targetContext!.toJson(),
  };
}

final class TutorAnalysisSnapshotAdapter {
  const TutorAnalysisSnapshotAdapter();

  TutorAnalysisSnapshot fromDocument(
    AnalysisDocument document, {
    AnalysisTarget? target,
  }) => TutorAnalysisSnapshot(
    insightIds: document.insights.map((insight) => insight.id).toList(),
    metricFacts: document.metrics
        .map(
          (metric) => TutorMetricFact(
            id: metric.id,
            confidence: metric.confidence,
            value: _metricFactValue(metric.value),
          ),
        )
        .toList(),
    hotspots: document.hotspots
        .map(
          (hotspot) => TutorHotspotRange(
            id: hotspot.id,
            startMicroseconds: hotspot.start.inMicroseconds,
            endMicroseconds: hotspot.end.inMicroseconds,
            confidence: hotspot.confidence,
          ),
        )
        .toList(),
    events: document.timeline.events
        .take(TutorSnapshotRedaction.maxEvents)
        .map(
          (event) => TutorEventFact(
            id: event.id,
            timeMicroseconds: event.time.inMicroseconds,
            confidence: event.confidence,
            kind: _eventKind(event),
          ),
        )
        .toList(),
    targetContext: target == null
        ? null
        : TutorTargetContext.fromTarget(target),
  );
}

String _eventKind(AnalysisEvent event) => switch (event) {
  OnsetEvent() => 'onset',
  StrumEvent() => 'strum',
  ChordChangeEvent() => 'chordChange',
  BeatEvent() => 'beat',
  NoteOnsetEvent() => 'noteOnset',
  SilenceRegionEvent() => 'silence',
  ClippingRegionEvent() => 'clipping',
};

Object? _metricFactValue(AnalysisMetricValue? value) => switch (value) {
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

abstract interface class TutorAnalysisSnapshotAdapterFactory {
  TutorAnalysisSnapshotAdapter create();
}

final class _DefaultTutorAnalysisSnapshotAdapterFactory
    implements TutorAnalysisSnapshotAdapterFactory {
  const _DefaultTutorAnalysisSnapshotAdapterFactory();

  @override
  TutorAnalysisSnapshotAdapter create() => const TutorAnalysisSnapshotAdapter();
}

final tutorAnalysisSnapshotAdapterFactoryProvider =
    Provider<TutorAnalysisSnapshotAdapterFactory>(
      (_) => const _DefaultTutorAnalysisSnapshotAdapterFactory(),
    );

/// Null while the OFF-by-default Tutor evidence integration is unavailable.
final tutorAnalysisSnapshotAdapterProvider =
    Provider<TutorAnalysisSnapshotAdapter?>((ref) {
      if (!ref.watch(appConfigProvider).flags.analysisTutorIntegrationEnabled) {
        return null;
      }
      return ref.watch(tutorAnalysisSnapshotAdapterFactoryProvider).create();
    });
