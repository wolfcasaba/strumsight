import 'activity_source.dart';
import 'evidence_trust.dart';

/// The only canonical input contract for future gamification processing.
const int learningActivityEventSchemaVersion = 1;

/// Immutable, versioned evidence that a learning activity occurred.
sealed class LearningActivityEvent {
  const LearningActivityEvent._({
    required this.eventId,
    required this.occurredAt,
    required this.epochDay,
    required this.source,
    required this.trust,
    required this.schemaVersion,
    required this.duration,
    required this.score,
  });

  final String eventId;
  final DateTime occurredAt;
  final int epochDay;
  final ActivitySource source;
  final EvidenceTrust trust;
  final int schemaVersion;
  final Duration duration;
  final double score;

  /// Stable JSON discriminator for this concrete activity category.
  String get type;

  Map<String, Object?> toJson() => <String, Object?>{
    'type': type,
    'eventId': eventId,
    'occurredAt': occurredAt.toIso8601String(),
    'epochDay': epochDay,
    'source': source.name,
    'trust': trust.name,
    'schemaVersion': schemaVersion,
    'durationMicroseconds': duration.inMicroseconds,
    'score': score,
  };

  /// Decodes the explicit type discriminator; field shapes are never inferred.
  static LearningActivityEvent fromJson(Object? json) {
    final decoded = _DecodedEvent.fromJson(json);
    return switch (decoded.type) {
      PracticeActivityEvent.typeCode => PracticeActivityEvent._fromDecoded(
        decoded,
      ),
      SongActivityEvent.typeCode => SongActivityEvent._fromDecoded(decoded),
      AnalysisActivityEvent.typeCode => AnalysisActivityEvent._fromDecoded(
        decoded,
      ),
      PlanActivityEvent.typeCode => PlanActivityEvent._fromDecoded(decoded),
      TutorActivityEvent.typeCode => TutorActivityEvent._fromDecoded(decoded),
      VisionActivityEvent.typeCode => VisionActivityEvent._fromDecoded(decoded),
      _ => throw ArgumentError.value(
        decoded.type,
        'type',
        'is not a supported learning activity event type',
      ),
    };
  }

  @override
  bool operator ==(Object other) =>
      runtimeType == other.runtimeType &&
      other is LearningActivityEvent &&
      eventId == other.eventId &&
      occurredAt == other.occurredAt &&
      epochDay == other.epochDay &&
      source == other.source &&
      trust == other.trust &&
      schemaVersion == other.schemaVersion &&
      duration == other.duration &&
      score == other.score;

  @override
  int get hashCode => Object.hash(
    runtimeType,
    eventId,
    occurredAt,
    epochDay,
    source,
    trust,
    schemaVersion,
    duration,
    score,
  );
}

final class PracticeActivityEvent extends LearningActivityEvent {
  factory PracticeActivityEvent({
    required String eventId,
    required DateTime occurredAt,
    required int epochDay,
    required ActivitySource source,
    required EvidenceTrust trust,
    required int schemaVersion,
    required Duration duration,
    required double score,
  }) {
    _validateEventFields(
      eventId: eventId,
      schemaVersion: schemaVersion,
      duration: duration,
      score: score,
    );
    return PracticeActivityEvent._(
      eventId: eventId,
      occurredAt: occurredAt,
      epochDay: epochDay,
      source: source,
      trust: trust,
      schemaVersion: schemaVersion,
      duration: duration,
      score: score,
    );
  }

  const PracticeActivityEvent._({
    required super.eventId,
    required super.occurredAt,
    required super.epochDay,
    required super.source,
    required super.trust,
    required super.schemaVersion,
    required super.duration,
    required super.score,
  }) : super._();

  static const String typeCode = 'practice';

  @override
  String get type => typeCode;

  static PracticeActivityEvent _fromDecoded(_DecodedEvent decoded) =>
      PracticeActivityEvent(
        eventId: decoded.eventId,
        occurredAt: decoded.occurredAt,
        epochDay: decoded.epochDay,
        source: decoded.source,
        trust: decoded.trust,
        schemaVersion: decoded.schemaVersion,
        duration: decoded.duration,
        score: decoded.score,
      );
}

final class SongActivityEvent extends LearningActivityEvent {
  factory SongActivityEvent({
    required String eventId,
    required DateTime occurredAt,
    required int epochDay,
    required ActivitySource source,
    required EvidenceTrust trust,
    required int schemaVersion,
    required Duration duration,
    required double score,
  }) {
    _validateEventFields(
      eventId: eventId,
      schemaVersion: schemaVersion,
      duration: duration,
      score: score,
    );
    return SongActivityEvent._(
      eventId: eventId,
      occurredAt: occurredAt,
      epochDay: epochDay,
      source: source,
      trust: trust,
      schemaVersion: schemaVersion,
      duration: duration,
      score: score,
    );
  }

  const SongActivityEvent._({
    required super.eventId,
    required super.occurredAt,
    required super.epochDay,
    required super.source,
    required super.trust,
    required super.schemaVersion,
    required super.duration,
    required super.score,
  }) : super._();

  static const String typeCode = 'song';

  @override
  String get type => typeCode;

  static SongActivityEvent _fromDecoded(_DecodedEvent decoded) =>
      SongActivityEvent(
        eventId: decoded.eventId,
        occurredAt: decoded.occurredAt,
        epochDay: decoded.epochDay,
        source: decoded.source,
        trust: decoded.trust,
        schemaVersion: decoded.schemaVersion,
        duration: decoded.duration,
        score: decoded.score,
      );
}

final class AnalysisActivityEvent extends LearningActivityEvent {
  factory AnalysisActivityEvent({
    required String eventId,
    required DateTime occurredAt,
    required int epochDay,
    required ActivitySource source,
    required EvidenceTrust trust,
    required int schemaVersion,
    required Duration duration,
    required double score,
  }) {
    _validateEventFields(
      eventId: eventId,
      schemaVersion: schemaVersion,
      duration: duration,
      score: score,
    );
    return AnalysisActivityEvent._(
      eventId: eventId,
      occurredAt: occurredAt,
      epochDay: epochDay,
      source: source,
      trust: trust,
      schemaVersion: schemaVersion,
      duration: duration,
      score: score,
    );
  }

  const AnalysisActivityEvent._({
    required super.eventId,
    required super.occurredAt,
    required super.epochDay,
    required super.source,
    required super.trust,
    required super.schemaVersion,
    required super.duration,
    required super.score,
  }) : super._();

  static const String typeCode = 'analysis';

  @override
  String get type => typeCode;

  static AnalysisActivityEvent _fromDecoded(_DecodedEvent decoded) =>
      AnalysisActivityEvent(
        eventId: decoded.eventId,
        occurredAt: decoded.occurredAt,
        epochDay: decoded.epochDay,
        source: decoded.source,
        trust: decoded.trust,
        schemaVersion: decoded.schemaVersion,
        duration: decoded.duration,
        score: decoded.score,
      );
}

final class PlanActivityEvent extends LearningActivityEvent {
  factory PlanActivityEvent({
    required String eventId,
    required DateTime occurredAt,
    required int epochDay,
    required ActivitySource source,
    required EvidenceTrust trust,
    required int schemaVersion,
    required Duration duration,
    required double score,
  }) {
    _validateEventFields(
      eventId: eventId,
      schemaVersion: schemaVersion,
      duration: duration,
      score: score,
    );
    return PlanActivityEvent._(
      eventId: eventId,
      occurredAt: occurredAt,
      epochDay: epochDay,
      source: source,
      trust: trust,
      schemaVersion: schemaVersion,
      duration: duration,
      score: score,
    );
  }

  const PlanActivityEvent._({
    required super.eventId,
    required super.occurredAt,
    required super.epochDay,
    required super.source,
    required super.trust,
    required super.schemaVersion,
    required super.duration,
    required super.score,
  }) : super._();

  static const String typeCode = 'plan';

  @override
  String get type => typeCode;

  static PlanActivityEvent _fromDecoded(_DecodedEvent decoded) =>
      PlanActivityEvent(
        eventId: decoded.eventId,
        occurredAt: decoded.occurredAt,
        epochDay: decoded.epochDay,
        source: decoded.source,
        trust: decoded.trust,
        schemaVersion: decoded.schemaVersion,
        duration: decoded.duration,
        score: decoded.score,
      );
}

final class TutorActivityEvent extends LearningActivityEvent {
  factory TutorActivityEvent({
    required String eventId,
    required DateTime occurredAt,
    required int epochDay,
    required ActivitySource source,
    required EvidenceTrust trust,
    required int schemaVersion,
    required Duration duration,
    required double score,
  }) {
    _validateEventFields(
      eventId: eventId,
      schemaVersion: schemaVersion,
      duration: duration,
      score: score,
    );
    return TutorActivityEvent._(
      eventId: eventId,
      occurredAt: occurredAt,
      epochDay: epochDay,
      source: source,
      trust: trust,
      schemaVersion: schemaVersion,
      duration: duration,
      score: score,
    );
  }

  const TutorActivityEvent._({
    required super.eventId,
    required super.occurredAt,
    required super.epochDay,
    required super.source,
    required super.trust,
    required super.schemaVersion,
    required super.duration,
    required super.score,
  }) : super._();

  static const String typeCode = 'tutor';

  @override
  String get type => typeCode;

  static TutorActivityEvent _fromDecoded(_DecodedEvent decoded) =>
      TutorActivityEvent(
        eventId: decoded.eventId,
        occurredAt: decoded.occurredAt,
        epochDay: decoded.epochDay,
        source: decoded.source,
        trust: decoded.trust,
        schemaVersion: decoded.schemaVersion,
        duration: decoded.duration,
        score: decoded.score,
      );
}

final class VisionActivityEvent extends LearningActivityEvent {
  factory VisionActivityEvent({
    required String eventId,
    required DateTime occurredAt,
    required int epochDay,
    required ActivitySource source,
    required EvidenceTrust trust,
    required int schemaVersion,
    required Duration duration,
    required double score,
  }) {
    _validateEventFields(
      eventId: eventId,
      schemaVersion: schemaVersion,
      duration: duration,
      score: score,
    );
    return VisionActivityEvent._(
      eventId: eventId,
      occurredAt: occurredAt,
      epochDay: epochDay,
      source: source,
      trust: trust,
      schemaVersion: schemaVersion,
      duration: duration,
      score: score,
    );
  }

  const VisionActivityEvent._({
    required super.eventId,
    required super.occurredAt,
    required super.epochDay,
    required super.source,
    required super.trust,
    required super.schemaVersion,
    required super.duration,
    required super.score,
  }) : super._();

  static const String typeCode = 'vision';

  @override
  String get type => typeCode;

  static VisionActivityEvent _fromDecoded(_DecodedEvent decoded) =>
      VisionActivityEvent(
        eventId: decoded.eventId,
        occurredAt: decoded.occurredAt,
        epochDay: decoded.epochDay,
        source: decoded.source,
        trust: decoded.trust,
        schemaVersion: decoded.schemaVersion,
        duration: decoded.duration,
        score: decoded.score,
      );
}

void _validateEventFields({
  required String eventId,
  required int schemaVersion,
  required Duration duration,
  required double score,
}) {
  if (eventId.trim().isEmpty) {
    throw ArgumentError.value(eventId, 'eventId', 'must not be empty or blank');
  }
  if (schemaVersion != learningActivityEventSchemaVersion) {
    throw ArgumentError.value(
      schemaVersion,
      'schemaVersion',
      'must equal $learningActivityEventSchemaVersion',
    );
  }
  if (duration.isNegative) {
    throw ArgumentError.value(duration, 'duration', 'must not be negative');
  }
  if (!score.isFinite || score < 0 || score > 1) {
    throw ArgumentError.value(
      score,
      'score',
      'must be finite and in the range [0, 1]',
    );
  }
}

final class _DecodedEvent {
  _DecodedEvent._({
    required this.type,
    required this.eventId,
    required this.occurredAt,
    required this.epochDay,
    required this.source,
    required this.trust,
    required this.schemaVersion,
    required this.duration,
    required this.score,
  });

  factory _DecodedEvent.fromJson(Object? json) {
    if (json is! Map<Object?, Object?>) {
      throw ArgumentError.value(json, 'json', 'must be a JSON object');
    }
    final values = <String, Object?>{};
    for (final entry in json.entries) {
      final key = entry.key;
      if (key is! String) {
        throw ArgumentError.value(key, 'json key', 'must be a String');
      }
      values[key] = entry.value;
    }

    final occurredAtText = _requireString(values, 'occurredAt');
    final occurredAt = DateTime.tryParse(occurredAtText);
    if (occurredAt == null) {
      throw ArgumentError.value(
        occurredAtText,
        'occurredAt',
        'must be an ISO-8601 timestamp',
      );
    }

    return _DecodedEvent._(
      type: _requireString(values, 'type'),
      eventId: _requireString(values, 'eventId'),
      occurredAt: occurredAt,
      epochDay: _requireInt(values, 'epochDay'),
      source: _activitySourceFromName(_requireString(values, 'source')),
      trust: _evidenceTrustFromName(_requireString(values, 'trust')),
      schemaVersion: _requireInt(values, 'schemaVersion'),
      duration: Duration(
        microseconds: _requireInt(values, 'durationMicroseconds'),
      ),
      score: _requireDouble(values, 'score'),
    );
  }

  final String type;
  final String eventId;
  final DateTime occurredAt;
  final int epochDay;
  final ActivitySource source;
  final EvidenceTrust trust;
  final int schemaVersion;
  final Duration duration;
  final double score;
}

String _requireString(Map<String, Object?> values, String key) {
  final value = values[key];
  if (value is! String) {
    throw ArgumentError.value(value, key, 'must be a String');
  }
  return value;
}

int _requireInt(Map<String, Object?> values, String key) {
  final value = values[key];
  if (value is! int) {
    throw ArgumentError.value(value, key, 'must be an int');
  }
  return value;
}

double _requireDouble(Map<String, Object?> values, String key) {
  final value = values[key];
  if (value is! num) {
    throw ArgumentError.value(value, key, 'must be a number');
  }
  return value.toDouble();
}

ActivitySource _activitySourceFromName(String name) {
  for (final source in ActivitySource.values) {
    if (source.name == name) return source;
  }
  throw ArgumentError.value(
    name,
    'source',
    'is not a supported activity source',
  );
}

EvidenceTrust _evidenceTrustFromName(String name) {
  for (final trust in EvidenceTrust.values) {
    if (trust.name == name) return trust;
  }
  throw ArgumentError.value(name, 'trust', 'is not a supported evidence trust');
}
