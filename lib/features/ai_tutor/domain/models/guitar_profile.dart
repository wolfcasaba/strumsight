import 'student_profile.dart';

/// Stable exception emitted when a guitar profile value is invalid.
class GuitarProfileValidationException implements Exception {
  GuitarProfileValidationException._(this.code);

  /// One of [GuitarProfileValidationCode]'s constants.
  final String code;

  @override
  String toString() => 'GuitarProfileValidationException($code)';
}

/// Stable machine-readable codes emitted by guitar profile validation.
abstract final class GuitarProfileValidationCode {
  static const String idEmpty = 'guitarProfile.id.empty';
  static const String nameEmpty = 'guitarProfile.name.empty';
  static const String stringCountOutOfRange =
      'guitarProfile.stringCount.outOfRange';
  static const String tuningLengthMismatch =
      'guitarProfile.tuning.lengthMismatch';
  static const String tuningStringEmpty = 'guitarProfile.tuning.string.empty';
  static const String capoFretOutOfRange = 'guitarProfile.capoFret.outOfRange';
}

const int minGuitarStringCount = 4;
const int maxGuitarStringCount = 12;
const int maxGuitarCapoFret = 24;

enum GuitarType { acousticSteel, classicalNylon, electric, unknown }

/// Guitar configuration and per-field provenance.
final class GuitarProfile {
  GuitarProfile({
    required String id,
    required ProfileField<String> name,
    required this.type,
    required ProfileField<List<String>> tuning,
    required ProfileField<int> stringCount,
    required ProfileField<int> capoFret,
    required this.isPrimary,
  }) : id = _id(id),
       name = ProfileField(_name(name.value), name.provenance),
       tuning = ProfileField(_immutableTuning(tuning.value), tuning.provenance),
       stringCount = stringCount,
       capoFret = capoFret {
    if (stringCount.value < minGuitarStringCount ||
        stringCount.value > maxGuitarStringCount) {
      throw GuitarProfileValidationException._(
        GuitarProfileValidationCode.stringCountOutOfRange,
      );
    }
    if (this.tuning.value.length != stringCount.value) {
      throw GuitarProfileValidationException._(
        GuitarProfileValidationCode.tuningLengthMismatch,
      );
    }
    if (capoFret.value < 0 || capoFret.value > maxGuitarCapoFret) {
      throw GuitarProfileValidationException._(
        GuitarProfileValidationCode.capoFretOutOfRange,
      );
    }
  }

  final String id;
  final ProfileField<String> name;
  final ProfileField<GuitarType> type;
  final ProfileField<List<String>> tuning;
  final ProfileField<int> stringCount;
  final ProfileField<int> capoFret;
  final ProfileField<bool> isPrimary;

  /// Resolves each guitar field without allowing inferred data over explicit data.
  GuitarProfile merge(GuitarProfile candidate) => GuitarProfile(
    id: id,
    name: name.resolveWith(candidate.name),
    type: type.resolveWith(candidate.type),
    tuning: tuning.resolveWith(candidate.tuning),
    stringCount: stringCount.resolveWith(candidate.stringCount),
    capoFret: capoFret.resolveWith(candidate.capoFret),
    isPrimary: isPrimary.resolveWith(candidate.isPrimary),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GuitarProfile &&
          other.id == id &&
          other.name == name &&
          other.type == type &&
          other.tuning == tuning &&
          other.stringCount == stringCount &&
          other.capoFret == capoFret &&
          other.isPrimary == isPrimary;

  @override
  int get hashCode =>
      Object.hash(id, name, type, tuning, stringCount, capoFret, isPrimary);
}

String _id(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw GuitarProfileValidationException._(
      GuitarProfileValidationCode.idEmpty,
    );
  }
  return trimmed;
}

String _name(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw GuitarProfileValidationException._(
      GuitarProfileValidationCode.nameEmpty,
    );
  }
  return trimmed;
}

List<String> _immutableTuning(List<String> values) {
  final normalized = <String>[];
  for (final value in values) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw GuitarProfileValidationException._(
        GuitarProfileValidationCode.tuningStringEmpty,
      );
    }
    normalized.add(trimmed);
  }
  return List<String>.unmodifiable(normalized);
}
