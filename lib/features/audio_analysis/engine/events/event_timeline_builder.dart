import 'dart:math' as math;

import 'package:strumsight/core/music/strum.dart' as legacy_core;

import '../../domain/analysis_event.dart';
import '../../domain/events/event_id.dart';
import '../../domain/preprocessed_audio.dart';
import '../analysis_provenance_builder.dart';
import '../legacy/legacy_evidence.dart';

/// The reason an event pair is retained only in diagnostic evidence.
enum EventSuppressionReason { duplicateSampleIndex, minimumSeparation }

/// An event that did not enter the public timeline, with its audit reason.
final class SuppressedEvent {
  const SuppressedEvent({required this.event, required this.reason});

  final AnalysisEvent event;
  final EventSuppressionReason reason;

  /// Timestamp retained with the suppressed evidence for later diagnostics.
  Duration get time => event.time;
}

/// Immutable output of one [EventTimelineBuilder] invocation.
final class EventTimelineBuildResult {
  EventTimelineBuildResult({
    required List<AnalysisEvent> events,
    required List<SuppressedEvent> suppressedEvents,
  }) : events = List<AnalysisEvent>.unmodifiable(events),
       suppressedEvents = List<SuppressedEvent>.unmodifiable(suppressedEvents);

  final List<AnalysisEvent> events;
  final List<SuppressedEvent> suppressedEvents;
}

/// Builds auditable V2 onset/strum evidence from the V1 legacy boundary.
///
/// The 50 ms exclusion mirrors the V1 BPM interval threshold. It compares
/// [Duration] values rather than sample indexes so native sample rates retain
/// the same temporal contract. Dynamics use original-rate PCM: absolute peak
/// in `[t, t + 20 ms]`, and RMS in `[t - 5 ms, t + 45 ms]`.
final class EventTimelineBuilder {
  const EventTimelineBuilder();

  /// Inclusive lower bound for separate logical strum/onset pairs.
  static const Duration minimumSeparation = Duration(milliseconds: 50);
  static const Duration _attackWindow = Duration(milliseconds: 20);
  static const Duration _rmsLead = Duration(milliseconds: 5);
  static const Duration _rmsTrail = Duration(milliseconds: 45);

  EventTimelineBuildResult build({
    required String runId,
    required LegacyEvidence evidence,
    required PreprocessedAudio audio,
  }) {
    final candidates = <_EventPair>[
      for (var index = 0; index < evidence.strums.length; index++)
        _buildPair(
          runId: runId,
          legacy: evidence.strums[index],
          originalOrder: index,
          provenance: evidence.provenance,
          audio: audio,
        ),
    ]..sort(_comparePairs);

    final events = <AnalysisEvent>[];
    final suppressedEvents = <SuppressedEvent>[];
    final seenSampleIndexes = <int>{};
    _EventPair? previousKeptPair;

    for (final pair in candidates) {
      final reason = _suppressionReason(
        pair: pair,
        seenSampleIndexes: seenSampleIndexes,
        previousKeptPair: previousKeptPair,
      );
      if (reason != null) {
        suppressedEvents.addAll(pair.suppress(reason));
        continue;
      }

      seenSampleIndexes.add(pair.sampleIndex);
      events.addAll(pair.events);
      previousKeptPair = pair;
    }

    return EventTimelineBuildResult(
      events: events,
      suppressedEvents: suppressedEvents,
    );
  }

  static int _comparePairs(_EventPair left, _EventPair right) {
    final bySample = left.sampleIndex.compareTo(right.sampleIndex);
    if (bySample != 0) return bySample;
    final byTime = left.time.compareTo(right.time);
    if (byTime != 0) return byTime;
    return left.originalOrder.compareTo(right.originalOrder);
  }

  static EventSuppressionReason? _suppressionReason({
    required _EventPair pair,
    required Set<int> seenSampleIndexes,
    required _EventPair? previousKeptPair,
  }) {
    if (seenSampleIndexes.contains(pair.sampleIndex)) {
      return EventSuppressionReason.duplicateSampleIndex;
    }
    if (previousKeptPair != null &&
        pair.time - previousKeptPair.time < minimumSeparation) {
      return EventSuppressionReason.minimumSeparation;
    }
    return null;
  }

  static _EventPair _buildPair({
    required String runId,
    required LegacyStrumEvidence legacy,
    required int originalOrder,
    required LegacyAnalyzerProvenance provenance,
    required PreprocessedAudio audio,
  }) {
    final sampleIndex = _sampleIndexFor(legacy.time, audio);
    final confidence = _normalizedConfidence(legacy.confidence);
    final confidenceSource = switch (provenance.strumRefinerSource) {
      StrumRefinerSource.crnn => EventConfidenceSources.crnn,
      StrumRefinerSource.none ||
      StrumRefinerSource.heuristic => EventConfidenceSources.heuristic,
    };
    final dynamics = _dynamicsAt(legacy.time, sampleIndex, audio);
    final onsetId = EventId.onset(runId: runId, sampleIndex: sampleIndex);
    final onset = OnsetEvent(
      id: onsetId,
      time: legacy.time,
      confidence: confidence,
      sampleIndex: sampleIndex,
      attackStrength: dynamics.attackStrength,
      localRms: dynamics.localRms,
      confidenceSource: confidenceSource,
      fallbackReason: provenance.fallbackReason,
    );
    final strum = StrumEvent(
      id: EventId.strum(runId: runId, sampleIndex: sampleIndex),
      time: legacy.time,
      confidence: confidence,
      sampleIndex: sampleIndex,
      direction: _directionFromLegacy(legacy.direction),
      directionConfidence: confidence,
      onsetEventId: onsetId,
      attackStrength: dynamics.attackStrength,
      localRms: dynamics.localRms,
      confidenceSource: confidenceSource,
      fallbackReason: provenance.fallbackReason,
    );
    return _EventPair(
      onset: onset,
      strum: strum,
      sampleIndex: sampleIndex,
      time: legacy.time,
      originalOrder: originalOrder,
    );
  }

  static int _sampleIndexFor(Duration time, PreprocessedAudio audio) {
    if (audio.originalSamples.isEmpty) return 0;
    return math.min(
      audio.durationToSampleIndex(time),
      audio.originalSamples.length - 1,
    );
  }

  static StrumDirection _directionFromLegacy(
    legacy_core.StrumDirection value,
  ) => switch (value) {
    legacy_core.StrumDirection.down => StrumDirection.down,
    legacy_core.StrumDirection.up => StrumDirection.up,
  };

  static double _normalizedConfidence(double value) {
    if (!value.isFinite) return 0;
    return value.clamp(0, 1).toDouble();
  }

  static _EventDynamics _dynamicsAt(
    Duration time,
    int sampleIndex,
    PreprocessedAudio audio,
  ) {
    final samples = audio.originalSamples;
    if (samples.isEmpty) return const _EventDynamics.zero();
    final attackEnd = _boundedSampleIndex(time + _attackWindow, audio);
    final rmsStart = _boundedSampleIndex(
      time > _rmsLead ? time - _rmsLead : Duration.zero,
      audio,
    );
    final rmsEnd = _boundedSampleIndex(time + _rmsTrail, audio);
    return _EventDynamics(
      attackStrength: _absolutePeak(samples, sampleIndex, attackEnd),
      localRms: _rms(samples, rmsStart, rmsEnd),
    );
  }

  static int _boundedSampleIndex(Duration time, PreprocessedAudio audio) => math
      .min(audio.durationToSampleIndex(time), audio.originalSamples.length - 1);

  static double _absolutePeak(List<double> samples, int start, int end) {
    var peak = 0.0;
    for (var index = start; index <= end; index++) {
      final sample = samples[index];
      if (sample.isFinite) peak = math.max(peak, sample.abs());
    }
    return peak;
  }

  static double _rms(List<double> samples, int start, int end) {
    var sumOfSquares = 0.0;
    var count = 0;
    for (var index = start; index <= end; index++) {
      final sample = samples[index];
      if (!sample.isFinite) continue;
      sumOfSquares += sample * sample;
      count++;
    }
    return count == 0 ? 0 : math.sqrt(sumOfSquares / count);
  }
}

final class _EventPair {
  const _EventPair({
    required this.onset,
    required this.strum,
    required this.sampleIndex,
    required this.time,
    required this.originalOrder,
  });

  final OnsetEvent onset;
  final StrumEvent strum;
  final int sampleIndex;
  final Duration time;
  final int originalOrder;

  List<AnalysisEvent> get events => <AnalysisEvent>[onset, strum];

  List<SuppressedEvent> suppress(EventSuppressionReason reason) =>
      <SuppressedEvent>[
        SuppressedEvent(event: onset, reason: reason),
        SuppressedEvent(event: strum, reason: reason),
      ];
}

final class _EventDynamics {
  const _EventDynamics({required this.attackStrength, required this.localRms});

  const _EventDynamics.zero() : attackStrength = 0, localRms = 0;

  final double attackStrength;
  final double localRms;
}
