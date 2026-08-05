import 'tutor_ids.dart';

/// Stable exception thrown when a structured tutor content block is invalid.
class TutorContentBlockValidationException implements Exception {
  TutorContentBlockValidationException._(this.code);

  /// One of [TutorContentBlockValidationCode]'s constants.
  final String code;

  @override
  String toString() => 'TutorContentBlockValidationException($code)';
}

/// Stable machine-readable codes emitted by content-block validation.
abstract final class TutorContentBlockValidationCode {
  static const String headingLevelOutOfRange =
      'tutorContentBlock.heading.levelOutOfRange';
  static const String bulletListEmpty = 'tutorContentBlock.bulletList.empty';
  static const String bulletItemEmpty =
      'tutorContentBlock.bulletList.itemEmpty';
  static const String unknownTypeEmpty = 'tutorContentBlock.unknown.typeEmpty';
  static const String rawJsonInvalid =
      'tutorContentBlock.unknown.rawJsonInvalid';
}

/// A structured, user-visible unit of tutor content.
sealed class TutorContentBlock {
  const TutorContentBlock();

  /// Stable discriminator persisted by [TutorConversationCodec].
  String get type;
}

/// Plain user-visible text.
final class TutorTextBlock extends TutorContentBlock {
  TutorTextBlock({required this.text});

  @override
  String get type => 'text';

  final String text;

  @override
  bool operator ==(Object other) =>
      other is TutorTextBlock && other.text == text;

  @override
  int get hashCode => Object.hash(type, text);
}

/// A heading with a Markdown-like level from one through six.
final class TutorHeadingBlock extends TutorContentBlock {
  TutorHeadingBlock({required this.text, required this.level}) {
    if (level < 1 || level > 6) {
      throw TutorContentBlockValidationException._(
        TutorContentBlockValidationCode.headingLevelOutOfRange,
      );
    }
  }

  @override
  String get type => 'heading';

  final String text;
  final int level;

  @override
  bool operator ==(Object other) =>
      other is TutorHeadingBlock && other.text == text && other.level == level;

  @override
  int get hashCode => Object.hash(type, text, level);
}

/// An ordered set of short instructional points.
final class TutorBulletListBlock extends TutorContentBlock {
  TutorBulletListBlock({required List<String> items})
    : items = List<String>.unmodifiable(items) {
    if (this.items.isEmpty) {
      throw TutorContentBlockValidationException._(
        TutorContentBlockValidationCode.bulletListEmpty,
      );
    }
    if (this.items.any((item) => item.trim().isEmpty)) {
      throw TutorContentBlockValidationException._(
        TutorContentBlockValidationCode.bulletItemEmpty,
      );
    }
  }

  @override
  String get type => 'bulletList';

  final List<String> items;

  @override
  bool operator ==(Object other) =>
      other is TutorBulletListBlock && _listEquals(other.items, items);

  @override
  int get hashCode => Object.hash(type, Object.hashAll(items));
}

/// A labeled metric supplied by an evidence-producing feature.
final class TutorMetricBlock extends TutorContentBlock {
  TutorMetricBlock({required this.label, required this.value, this.unit});

  @override
  String get type => 'metric';

  final String label;
  final String value;
  final String? unit;

  @override
  bool operator ==(Object other) =>
      other is TutorMetricBlock &&
      other.label == label &&
      other.value == value &&
      other.unit == unit;

  @override
  int get hashCode => Object.hash(type, label, value, unit);
}

/// A concise evidence reference and its user-visible summary.
final class TutorEvidenceBlock extends TutorContentBlock {
  TutorEvidenceBlock({required this.evidenceId, required this.summary});

  @override
  String get type => 'evidence';

  final String evidenceId;
  final String summary;

  @override
  bool operator ==(Object other) =>
      other is TutorEvidenceBlock &&
      other.evidenceId == evidenceId &&
      other.summary == summary;

  @override
  int get hashCode => Object.hash(type, evidenceId, summary);
}

/// A user-visible source reference.
final class TutorSourceBlock extends TutorContentBlock {
  TutorSourceBlock({required this.title, required this.reference});

  @override
  String get type => 'source';

  final String title;
  final String reference;

  @override
  bool operator ==(Object other) =>
      other is TutorSourceBlock &&
      other.title == title &&
      other.reference == reference;

  @override
  int get hashCode => Object.hash(type, title, reference);
}

/// A reference to an action that still needs the user's confirmation.
final class TutorActionBlock extends TutorContentBlock {
  TutorActionBlock({required this.actionId, required this.label});

  @override
  String get type => 'action';

  final TutorActionId actionId;
  final String label;

  @override
  bool operator ==(Object other) =>
      other is TutorActionBlock &&
      other.actionId == actionId &&
      other.label == label;

  @override
  int get hashCode => Object.hash(type, actionId, label);
}

/// A reference to a structured practice-plan draft.
final class TutorPracticePlanBlock extends TutorContentBlock {
  TutorPracticePlanBlock({required this.planId, required this.title});

  @override
  String get type => 'practicePlan';

  final String planId;
  final String title;

  @override
  bool operator ==(Object other) =>
      other is TutorPracticePlanBlock &&
      other.planId == planId &&
      other.title == title;

  @override
  int get hashCode => Object.hash(type, planId, title);
}

/// A non-fatal warning for the learner.
final class TutorWarningBlock extends TutorContentBlock {
  TutorWarningBlock({required this.message});

  @override
  String get type => 'warning';

  final String message;

  @override
  bool operator ==(Object other) =>
      other is TutorWarningBlock && other.message == message;

  @override
  int get hashCode => Object.hash(type, message);
}

/// A user-visible failure message.
final class TutorErrorBlock extends TutorContentBlock {
  TutorErrorBlock({required this.message});

  @override
  String get type => 'error';

  final String message;

  @override
  bool operator ==(Object other) =>
      other is TutorErrorBlock && other.message == message;

  @override
  int get hashCode => Object.hash(type, message);
}

/// Preserves an unknown future content block instead of silently dropping it.
final class TutorUnknownContentBlock extends TutorContentBlock {
  TutorUnknownContentBlock({
    required String originalType,
    required Map<String, Object?> rawJson,
  }) : originalType = originalType.trim(),
       rawJson = _freezeMap(rawJson) {
    if (this.originalType.isEmpty) {
      throw TutorContentBlockValidationException._(
        TutorContentBlockValidationCode.unknownTypeEmpty,
      );
    }
  }

  @override
  String get type => 'unknown';

  /// The discriminator supplied by a future schema version.
  final String originalType;

  /// The complete decoded JSON object, including its original type.
  final Map<String, Object?> rawJson;

  @override
  bool operator ==(Object other) =>
      other is TutorUnknownContentBlock &&
      other.originalType == originalType &&
      _jsonEquals(other.rawJson, rawJson);

  @override
  int get hashCode => Object.hash(originalType, _jsonHash(rawJson));
}

bool _listEquals<T>(List<T> left, List<T> right) {
  if (identical(left, right)) return true;
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

Map<String, Object?> _freezeMap(Map<String, Object?> source) {
  final frozen = <String, Object?>{};
  for (final entry in source.entries) {
    frozen[entry.key] = _freezeJson(entry.value);
  }
  return Map<String, Object?>.unmodifiable(frozen);
}

Object? _freezeJson(Object? value) {
  if (value == null || value is String || value is num || value is bool) {
    return value;
  }
  if (value is List) {
    return List<Object?>.unmodifiable(value.map(_freezeJson));
  }
  if (value is Map) {
    final mapped = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw TutorContentBlockValidationException._(
          TutorContentBlockValidationCode.rawJsonInvalid,
        );
      }
      mapped[entry.key as String] = _freezeJson(entry.value);
    }
    return Map<String, Object?>.unmodifiable(mapped);
  }
  throw TutorContentBlockValidationException._(
    TutorContentBlockValidationCode.rawJsonInvalid,
  );
}

bool _jsonEquals(Object? left, Object? right) {
  if (identical(left, right)) return true;
  if (left is List && right is List) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (!_jsonEquals(left[index], right[index])) return false;
    }
    return true;
  }
  if (left is Map && right is Map) {
    if (left.length != right.length) return false;
    for (final entry in left.entries) {
      if (!right.containsKey(entry.key) ||
          !_jsonEquals(entry.value, right[entry.key])) {
        return false;
      }
    }
    return true;
  }
  return left == right;
}

int _jsonHash(Object? value) {
  if (value is List) return Object.hashAll(value.map(_jsonHash));
  if (value is Map) {
    var hash = 0;
    for (final entry in value.entries) {
      hash ^= Object.hash(entry.key, _jsonHash(entry.value));
    }
    return hash;
  }
  return value.hashCode;
}
