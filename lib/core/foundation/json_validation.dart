/// Explicit decode-time validation for persisted records (SDD Ch2 Kör 7 §7.1).
///
/// Every persisted model decodes through these helpers instead of raw casts, so
/// a malformed record fails with a *named reason* the storage layer can log and
/// skip — rather than a `TypeError` that says nothing about which field of which
/// record was wrong.
///
/// The helpers deliberately never carry the offending **value** into the
/// exception: a record is user content, and failure text ends up in logs.
library;

/// Why one persisted record could not be decoded.
///
/// The [reason] strings are stable machine identifiers (they show up in logs
/// and tests); the human explanation belongs in the code that reads them.
class JsonRecordException implements Exception {
  const JsonRecordException(this.reason, {this.field});

  /// One of [RecordDecodeReason]'s constants.
  final String reason;

  /// The field that failed, when the failure is scoped to one.
  final String? field;

  @override
  String toString() =>
      'JsonRecordException($reason${field == null ? '' : ', field: $field'})';
}

/// Stable reasons a record can be rejected.
abstract final class RecordDecodeReason {
  static const String missing = 'missing';
  static const String notAnObject = 'not_an_object';
  static const String notAString = 'not_a_string';
  static const String notANumber = 'not_a_number';
  static const String notAList = 'not_a_list';
  static const String empty = 'empty';
  static const String outOfRange = 'out_of_range';
  static const String badDate = 'bad_date';
  static const String unknownEnum = 'unknown_enum';
  static const String tooLong = 'too_long';
}

/// The decoded JSON object, or a [JsonRecordException] if [value] is not one.
Map<String, dynamic> requireObject(Object? value, {String? field}) {
  if (value is Map<String, dynamic>) return value;
  throw JsonRecordException(RecordDecodeReason.notAnObject, field: field);
}

/// A required, non-empty string field (e.g. an id, a name, a chord label).
///
/// Empty is rejected by default: a persisted record with a blank chord label or
/// id is not a usable record, and silently keeping it would push the problem
/// into the UI.
String requireString(
  Map<String, dynamic> json,
  String field, {
  bool allowEmpty = false,
  int maxLength = 4096,
}) {
  final value = json[field];
  if (value == null) {
    throw JsonRecordException(RecordDecodeReason.missing, field: field);
  }
  if (value is! String) {
    throw JsonRecordException(RecordDecodeReason.notAString, field: field);
  }
  if (!allowEmpty && value.isEmpty) {
    throw JsonRecordException(RecordDecodeReason.empty, field: field);
  }
  if (value.length > maxLength) {
    throw JsonRecordException(RecordDecodeReason.tooLong, field: field);
  }
  return value;
}

/// A required integer field, range-checked. [min] defaults to 0 so the common
/// "a duration/count can never be negative" rule is the default, not an
/// afterthought.
int requireInt(
  Map<String, dynamic> json,
  String field, {
  int min = 0,
  int max = 1 << 40,
}) => _requireNum(json, field, min.toDouble(), max.toDouble()).toInt();

/// A required floating-point field, range-checked. NaN and infinity are
/// rejected — they poison every later computation and never come from a
/// legitimate write.
double requireDouble(
  Map<String, dynamic> json,
  String field, {
  double min = 0,
  double max = double.maxFinite,
}) => _requireNum(json, field, min, max).toDouble();

/// An optional floating-point field: absent stays absent, present is validated.
double? optionalDouble(
  Map<String, dynamic> json,
  String field, {
  double min = 0,
  double max = double.maxFinite,
}) =>
    json[field] == null ? null : requireDouble(json, field, min: min, max: max);

/// An optional integer field with a [fallback] for records written before the
/// field existed.
int optionalInt(
  Map<String, dynamic> json,
  String field, {
  required int fallback,
  int min = 0,
  int max = 1 << 40,
}) => json[field] == null
    ? fallback
    : requireInt(json, field, min: min, max: max);

/// An optional boolean field with a [fallback]; a non-boolean is a bad record.
bool optionalBool(
  Map<String, dynamic> json,
  String field, {
  required bool fallback,
}) {
  final value = json[field];
  if (value == null) return fallback;
  if (value is! bool) {
    throw JsonRecordException(RecordDecodeReason.notAString, field: field);
  }
  return value;
}

num _requireNum(
  Map<String, dynamic> json,
  String field,
  double min,
  double max,
) {
  final value = json[field];
  if (value == null) {
    throw JsonRecordException(RecordDecodeReason.missing, field: field);
  }
  if (value is! num || value.isNaN || value.isInfinite) {
    throw JsonRecordException(RecordDecodeReason.notANumber, field: field);
  }
  if (value < min || value > max) {
    throw JsonRecordException(RecordDecodeReason.outOfRange, field: field);
  }
  return value;
}

/// A required ISO-8601 timestamp. An unparseable date is a bad record, not a
/// reason to substitute "now" — a fabricated timestamp would silently reorder
/// the user's history.
DateTime requireDateTime(Map<String, dynamic> json, String field) {
  final raw = requireString(json, field);
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) {
    throw JsonRecordException(RecordDecodeReason.badDate, field: field);
  }
  return parsed;
}

/// A required list field, length-bounded.
///
/// The bound is not cosmetic: a corrupt or hand-edited blob claiming a
/// million-element list would otherwise be decoded into memory before anything
/// noticed.
List<Object?> requireList(
  Map<String, dynamic> json,
  String field, {
  required int maxLength,
}) {
  final value = json[field];
  if (value == null) {
    throw JsonRecordException(RecordDecodeReason.missing, field: field);
  }
  if (value is! List) {
    throw JsonRecordException(RecordDecodeReason.notAList, field: field);
  }
  if (value.length > maxLength) {
    throw JsonRecordException(RecordDecodeReason.tooLong, field: field);
  }
  return value;
}

/// A required list of non-empty strings (chord labels, song ids), bounded.
List<String> requireStringList(
  Map<String, dynamic> json,
  String field, {
  required int maxLength,
}) {
  final raw = requireList(json, field, maxLength: maxLength);
  return [
    for (final entry in raw)
      if (entry is String && entry.isNotEmpty)
        entry
      else
        throw JsonRecordException(
          entry is String
              ? RecordDecodeReason.empty
              : RecordDecodeReason.notAString,
          field: field,
        ),
  ];
}

/// A required enum value, matched by [names] — an unknown name is a bad record.
///
/// Use this where a wrong value must not be guessed at. Where a *degrade* is
/// the better product answer (an older build meeting a newer source name), the
/// model does it explicitly and documents why.
T requireEnumByName<T extends Enum>(
  Map<String, dynamic> json,
  String field,
  List<T> values,
) {
  final name = requireString(json, field);
  for (final value in values) {
    if (value.name == name) return value;
  }
  throw JsonRecordException(RecordDecodeReason.unknownEnum, field: field);
}
