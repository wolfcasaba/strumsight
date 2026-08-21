import 'package:strumsight/core/music/strum.dart';

import '../../data/migration/legacy_daily_challenge_adapter.dart';

/// Current schema for persisted [DailyChallengeDefinition] records.
const int challengeDefinitionSchemaVersion = 1;

/// The closed, typed vocabulary of V2 daily-challenge kinds.
///
/// The legacy strum-pattern branch is represented as [strumPattern] and is
/// **always** available because it is self-contained; the four newer kinds
/// reference content that lives in a per-device catalog and may be empty
/// offline (see [DailyChallengeContentCatalog] in `daily_challenge_service.dart`).
enum DailyChallengeType {
  strumPattern,
  chordChange,
  rhythm,
  songSection,
  timing,
}

/// A sealed, versioned definition of one V2 daily challenge. Each subtype is a
/// typed reference to its underlying content — chord, rhythm pattern, song
/// section, or timing target — so an offline generator can pick only IDs that
/// are installed on the device (ADR 0387 Decision 4).
sealed class DailyChallengeDefinition {
  const DailyChallengeDefinition();

  DailyChallengeType get type;

  /// The content identifier this challenge references. For [StrumPatternChallenge]
  /// the value is `null` because the legacy generator is self-contained.
  String? get contentId;

  Map<String, Object?> toJson();

  factory DailyChallengeDefinition.fromJson(Object? json) {
    final object = _requireObject(json, 'json');
    final type = _requireString(object, 'type');
    return switch (type) {
      'strumPattern' => StrumPatternChallenge.fromJson(object),
      'chordChange' => ChordChangeChallenge.fromJson(object),
      'rhythm' => RhythmChallenge.fromJson(object),
      'songSection' => SongSectionChallenge.fromJson(object),
      'timing' => TimingChallenge.fromJson(object),
      _ => throw ArgumentError.value(type, 'type', 'is not supported'),
    };
  }
}

/// The legacy, self-contained strum-pattern challenge produced by the
/// [LegacyDailyChallengeAdapter]. The pattern is byte-identical with the
/// shipping `DailyChallenge.forDay` output (ADR 0387 Decision 1).
final class StrumPatternChallenge extends DailyChallengeDefinition {
  const StrumPatternChallenge({required this.pattern, required this.name});

  /// The byte-identical [StrumDirection] sequence from the legacy generator.
  final List<StrumDirection> pattern;

  /// The rotating human-readable name copied from the legacy generator.
  final String name;

  @override
  DailyChallengeType get type => DailyChallengeType.strumPattern;

  @override
  String? get contentId => null;

  String get glyphs =>
      pattern.map((d) => d == StrumDirection.down ? '↓' : '↑').join(' ');

  int get downCount => pattern.where((d) => d == StrumDirection.down).length;
  int get upCount => pattern.length - downCount;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'type': 'strumPattern',
    'pattern': pattern.map((d) => d.name).toList(growable: false),
    'name': name,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StrumPatternChallenge &&
          _patternEquals(other.pattern, pattern) &&
          other.name == name;

  @override
  int get hashCode => Object.hash(Object.hashAll(pattern), name);

  factory StrumPatternChallenge.fromJson(Map<String, Object?> object) {
    final patternRaw = object['pattern'];
    if (patternRaw is! List<Object?> ||
        patternRaw.any((item) => item is! String)) {
      throw ArgumentError.value(
        patternRaw,
        'pattern',
        'must be a list of StrumDirection names',
      );
    }
    final pattern = <StrumDirection>[
      for (final code in patternRaw.cast<String>()) _directionFromName(code),
    ];
    return StrumPatternChallenge(
      pattern: List<StrumDirection>.unmodifiable(pattern),
      name: _requireString(object, 'name'),
    );
  }
}

/// A challenge to transition between two installed chord shapes within a fixed
/// beat budget. Both chord IDs must exist on the device.
final class ChordChangeChallenge extends DailyChallengeDefinition {
  ChordChangeChallenge({
    required this.fromChordId,
    required this.toChordId,
    required this.beats,
  }) {
    if (fromChordId.trim().isEmpty) {
      throw ArgumentError.value(
        fromChordId,
        'fromChordId',
        'must not be blank',
      );
    }
    if (toChordId.trim().isEmpty) {
      throw ArgumentError.value(toChordId, 'toChordId', 'must not be blank');
    }
    if (beats < 1) {
      throw ArgumentError.value(beats, 'beats', 'must be positive');
    }
  }

  final String fromChordId;
  final String toChordId;
  final int beats;

  @override
  DailyChallengeType get type => DailyChallengeType.chordChange;

  @override
  String? get contentId => '$fromChordId>$toChordId';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'type': 'chordChange',
    'fromChordId': fromChordId,
    'toChordId': toChordId,
    'beats': beats,
  };

  factory ChordChangeChallenge.fromJson(Map<String, Object?> object) =>
      ChordChangeChallenge(
        fromChordId: _requireString(object, 'fromChordId'),
        toChordId: _requireString(object, 'toChordId'),
        beats: _requireInt(object, 'beats'),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChordChangeChallenge &&
          other.fromChordId == fromChordId &&
          other.toChordId == toChordId &&
          other.beats == beats;

  @override
  int get hashCode => Object.hash(fromChordId, toChordId, beats);
}

/// A challenge to play a rhythm pattern at a target tempo. The pattern is one
/// installed rhythm content ID.
final class RhythmChallenge extends DailyChallengeDefinition {
  RhythmChallenge({required this.contentId, required this.targetBpm}) {
    if (contentId.trim().isEmpty) {
      throw ArgumentError.value(contentId, 'contentId', 'must not be blank');
    }
    if (targetBpm < 1) {
      throw ArgumentError.value(targetBpm, 'targetBpm', 'must be positive');
    }
  }

  @override
  final String contentId;
  final int targetBpm;

  @override
  DailyChallengeType get type => DailyChallengeType.rhythm;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'type': 'rhythm',
    'contentId': contentId,
    'targetBpm': targetBpm,
  };

  factory RhythmChallenge.fromJson(Map<String, Object?> object) =>
      RhythmChallenge(
        contentId: _requireString(object, 'contentId'),
        targetBpm: _requireInt(object, 'targetBpm'),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RhythmChallenge &&
          other.contentId == contentId &&
          other.targetBpm == targetBpm;

  @override
  int get hashCode => Object.hash(contentId, targetBpm);
}

/// A challenge to play a specific section of an installed song for a given
/// number of repetitions.
final class SongSectionChallenge extends DailyChallengeDefinition {
  SongSectionChallenge({
    required this.songId,
    required this.sectionId,
    required this.repetitions,
  }) {
    if (songId.trim().isEmpty) {
      throw ArgumentError.value(songId, 'songId', 'must not be blank');
    }
    if (sectionId.trim().isEmpty) {
      throw ArgumentError.value(sectionId, 'sectionId', 'must not be blank');
    }
    if (repetitions < 1) {
      throw ArgumentError.value(repetitions, 'repetitions', 'must be positive');
    }
  }

  final String songId;
  final String sectionId;
  final int repetitions;

  @override
  DailyChallengeType get type => DailyChallengeType.songSection;

  @override
  String? get contentId => '$songId/$sectionId';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'type': 'songSection',
    'songId': songId,
    'sectionId': sectionId,
    'repetitions': repetitions,
  };

  factory SongSectionChallenge.fromJson(Map<String, Object?> object) =>
      SongSectionChallenge(
        songId: _requireString(object, 'songId'),
        sectionId: _requireString(object, 'sectionId'),
        repetitions: _requireInt(object, 'repetitions'),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SongSectionChallenge &&
          other.songId == songId &&
          other.sectionId == sectionId &&
          other.repetitions == repetitions;

  @override
  int get hashCode => Object.hash(songId, sectionId, repetitions);
}

/// A challenge to hit a target strum-tempo window on a rhythm content ID.
final class TimingChallenge extends DailyChallengeDefinition {
  TimingChallenge({required this.contentId, required this.targetWindowMs}) {
    if (contentId.trim().isEmpty) {
      throw ArgumentError.value(contentId, 'contentId', 'must not be blank');
    }
    if (targetWindowMs < 1) {
      throw ArgumentError.value(
        targetWindowMs,
        'targetWindowMs',
        'must be positive',
      );
    }
  }

  @override
  final String contentId;
  final int targetWindowMs;

  @override
  DailyChallengeType get type => DailyChallengeType.timing;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'type': 'timing',
    'contentId': contentId,
    'targetWindowMs': targetWindowMs,
  };

  factory TimingChallenge.fromJson(Map<String, Object?> object) =>
      TimingChallenge(
        contentId: _requireString(object, 'contentId'),
        targetWindowMs: _requireInt(object, 'targetWindowMs'),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimingChallenge &&
          other.contentId == contentId &&
          other.targetWindowMs == targetWindowMs;

  @override
  int get hashCode => Object.hash(contentId, targetWindowMs);
}

Map<String, Object?> _requireObject(Object? value, String field) {
  if (value is Map<String, Object?>) return value;
  throw ArgumentError.value(value, field, 'must be an object');
}

String _requireString(Map<String, Object?> object, String field) {
  final value = object[field];
  if (value is String) return value;
  throw ArgumentError.value(value, field, 'must be a string');
}

int _requireInt(Map<String, Object?> object, String field) {
  final value = object[field];
  if (value is int) return value;
  throw ArgumentError.value(value, field, 'must be an integer');
}

StrumDirection _directionFromName(String name) {
  for (final direction in StrumDirection.values) {
    if (direction.name == name) return direction;
  }
  throw ArgumentError.value(name, 'StrumDirection', 'is not supported');
}

bool _patternEquals(List<StrumDirection> left, List<StrumDirection> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
