import 'dart:convert';

import '../../domain/models/guitar_profile.dart';
import '../../domain/models/learning_goal.dart';
import '../../domain/models/student_profile.dart';
import '../../domain/models/tutor_consent.dart';

/// Stable failure emitted when persisted tutor profile data cannot be read.
class TutorProfileCodecException implements Exception {
  TutorProfileCodecException._(this.code, {this.field});

  /// One of [TutorProfileCodecErrorCode]'s constants.
  final String code;
  final String? field;

  @override
  String toString() =>
      'TutorProfileCodecException($code${field == null ? '' : ', field: $field'})';
}

/// Stable machine-readable failures emitted by [TutorProfileCodec].
abstract final class TutorProfileCodecErrorCode {
  static const String malformedJson = 'tutorProfile.codec.malformedJson';
  static const String notAnObject = 'tutorProfile.codec.notAnObject';
  static const String schemaVersionMissing =
      'tutorProfile.codec.schemaVersion.missing';
  static const String schemaVersionUnknown =
      'tutorProfile.codec.schemaVersion.unknown';
  static const String documentTypeUnknown =
      'tutorProfile.codec.documentType.unknown';
  static const String fieldMissing = 'tutorProfile.codec.field.missing';
  static const String fieldInvalid = 'tutorProfile.codec.field.invalid';
  static const String enumUnknown = 'tutorProfile.codec.enum.unknown';
  static const String deadlineInvalid = 'tutorProfile.codec.deadline.invalid';
}

/// Deterministic profile codec that ignores unknown fields and rejects missing ones.
final class TutorProfileCodec {
  const TutorProfileCodec();

  /// The highest schema version this codec can decode.
  static const int supportedSchemaVersion = 1;

  /// Produces canonical UTF-8 JSON for a student profile.
  List<int> encodeStudentProfile(StudentProfile profile) => _encodeEnvelope(
    _studentProfileType,
    'studentProfile',
    _studentToMap(profile),
  );

  /// Decodes a version-one student profile envelope.
  StudentProfile decodeStudentProfile(List<int> bytes) {
    final root = _decodeEnvelope(bytes, _studentProfileType);
    try {
      return StudentProfile(
        experienceLevel: _enumField(
          root,
          'studentProfile',
          'experienceLevel',
          StudentExperienceLevel.values,
        ),
        preferredStyles: _stringsField(
          root,
          'studentProfile',
          'preferredStyles',
        ),
        weeklyPracticeMinutes: _nullableIntField(
          root,
          'studentProfile',
          'weeklyPracticeMinutes',
        ),
        explanationLength: _enumField(
          root,
          'studentProfile',
          'explanationLength',
          TutorExplanationLength.values,
        ),
        feedbackDirectness: _enumField(
          root,
          'studentProfile',
          'feedbackDirectness',
          TutorFeedbackDirectness.values,
        ),
        knownTechniques: _stringsField(
          root,
          'studentProfile',
          'knownTechniques',
        ),
        avoidList: _stringsField(root, 'studentProfile', 'avoidList'),
        locale: _stringField(root, 'studentProfile', 'locale'),
      );
    } on StudentProfileValidationException {
      throw TutorProfileCodecException._(
        TutorProfileCodecErrorCode.fieldInvalid,
        field: 'studentProfile',
      );
    }
  }

  /// Produces canonical UTF-8 JSON for a guitar profile.
  List<int> encodeGuitarProfile(GuitarProfile profile) => _encodeEnvelope(
    _guitarProfileType,
    'guitarProfile',
    _guitarToMap(profile),
  );

  /// Decodes a version-one guitar profile envelope.
  GuitarProfile decodeGuitarProfile(List<int> bytes) {
    final root = _decodeEnvelope(bytes, _guitarProfileType);
    final profile = _requiredObject(root, 'guitarProfile');
    try {
      return GuitarProfile(
        id: _requiredString(profile, 'id'),
        name: _stringField(root, 'guitarProfile', 'name'),
        type: _enumField(root, 'guitarProfile', 'type', GuitarType.values),
        tuning: _stringsField(root, 'guitarProfile', 'tuning'),
        stringCount: _intField(root, 'guitarProfile', 'stringCount'),
        capoFret: _intField(root, 'guitarProfile', 'capoFret'),
        isPrimary: _boolField(root, 'guitarProfile', 'isPrimary'),
      );
    } on GuitarProfileValidationException {
      throw TutorProfileCodecException._(
        TutorProfileCodecErrorCode.fieldInvalid,
        field: 'guitarProfile',
      );
    }
  }

  /// Produces canonical UTF-8 JSON for a learning goal.
  List<int> encodeLearningGoal(LearningGoal goal) =>
      _encodeEnvelope(_learningGoalType, 'learningGoal', _goalToMap(goal));

  /// Decodes a version-one learning goal envelope.
  LearningGoal decodeLearningGoal(List<int> bytes) {
    final root = _decodeEnvelope(bytes, _learningGoalType);
    final goal = _requiredObject(root, 'learningGoal');
    try {
      return LearningGoal(
        id: _requiredString(goal, 'id'),
        statement: _requiredString(goal, 'statement'),
        category: _enumValue(
          _requiredString(goal, 'category'),
          LearningGoalCategory.values,
          'learningGoal.category',
        ),
        priority: _enumValue(
          _requiredString(goal, 'priority'),
          LearningGoalPriority.values,
          'learningGoal.priority',
        ),
        deadline: _optionalUtcDeadline(goal),
        status: _enumValue(
          _requiredString(goal, 'status'),
          LearningGoalStatus.values,
          'learningGoal.status',
        ),
      );
    } on LearningGoalValidationException {
      throw TutorProfileCodecException._(
        TutorProfileCodecErrorCode.fieldInvalid,
        field: 'learningGoal',
      );
    }
  }

  /// Produces canonical UTF-8 JSON for granular tutor consent.
  List<int> encodeTutorConsent(TutorConsent consent) =>
      _encodeEnvelope(_tutorConsentType, 'tutorConsent', <String, Object?>{
        'modelUseGranted': consent.modelUseGranted,
        'persistentStorageGranted': consent.persistentStorageGranted,
        'evaluationWithRedactionGranted':
            consent.evaluationWithRedactionGranted,
      });

  /// Decodes a version-one granular tutor consent envelope.
  TutorConsent decodeTutorConsent(List<int> bytes) {
    final root = _decodeEnvelope(bytes, _tutorConsentType);
    final consent = _requiredObject(root, 'tutorConsent');
    return TutorConsent(
      modelUseGranted: _requiredBool(consent, 'modelUseGranted'),
      persistentStorageGranted: _requiredBool(
        consent,
        'persistentStorageGranted',
      ),
      evaluationWithRedactionGranted: _requiredBool(
        consent,
        'evaluationWithRedactionGranted',
      ),
    );
  }
}

const String _studentProfileType = 'studentProfile';
const String _guitarProfileType = 'guitarProfile';
const String _learningGoalType = 'learningGoal';
const String _tutorConsentType = 'tutorConsent';

List<int> _encodeEnvelope(
  String type,
  String field,
  Map<String, Object?> payload,
) => utf8.encode(
  jsonEncode(<String, Object?>{
    'schemaVersion': TutorProfileCodec.supportedSchemaVersion,
    'type': type,
    field: payload,
  }),
);

Map<String, Object?> _studentToMap(StudentProfile profile) => <String, Object?>{
  'experienceLevel': _enumFieldToMap(profile.experienceLevel),
  'preferredStyles': _stringsFieldToMap(profile.preferredStyles),
  'weeklyPracticeMinutes': _fieldToMap(
    profile.weeklyPracticeMinutes.value,
    profile.weeklyPracticeMinutes.provenance,
  ),
  'explanationLength': _enumFieldToMap(profile.explanationLength),
  'feedbackDirectness': _enumFieldToMap(profile.feedbackDirectness),
  'knownTechniques': _stringsFieldToMap(profile.knownTechniques),
  'avoidList': _stringsFieldToMap(profile.avoidList),
  'locale': _fieldToMap(profile.locale.value, profile.locale.provenance),
};

Map<String, Object?> _guitarToMap(GuitarProfile profile) => <String, Object?>{
  'id': profile.id,
  'name': _fieldToMap(profile.name.value, profile.name.provenance),
  'type': _enumFieldToMap(profile.type),
  'tuning': _stringsFieldToMap(profile.tuning),
  'stringCount': _fieldToMap(
    profile.stringCount.value,
    profile.stringCount.provenance,
  ),
  'capoFret': _fieldToMap(profile.capoFret.value, profile.capoFret.provenance),
  'isPrimary': _fieldToMap(
    profile.isPrimary.value,
    profile.isPrimary.provenance,
  ),
};

Map<String, Object?> _goalToMap(LearningGoal goal) => <String, Object?>{
  'id': goal.id,
  'statement': goal.statement,
  'category': goal.category.name,
  'priority': goal.priority.name,
  'deadline': goal.deadline?.toUtc().toIso8601String(),
  'status': goal.status.name,
};

Map<String, Object?> _fieldToMap(
  Object? value,
  StudentProfileFieldProvenance provenance,
) => <String, Object?>{'value': value, 'provenance': provenance.name};

Map<String, Object?> _enumFieldToMap<T extends Enum>(ProfileField<T> field) =>
    _fieldToMap(field.value.name, field.provenance);

Map<String, Object?> _stringsFieldToMap(ProfileField<List<String>> field) =>
    _fieldToMap(<Object?>[...field.value], field.provenance);

Map<String, Object?> _decodeEnvelope(List<int> bytes, String expectedType) {
  final Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(bytes));
  } on FormatException {
    throw TutorProfileCodecException._(
      TutorProfileCodecErrorCode.malformedJson,
    );
  }
  final root = _asObjectMap(decoded, TutorProfileCodecErrorCode.notAnObject);
  final schemaVersion = _requiredInt(
    root,
    'schemaVersion',
    TutorProfileCodecErrorCode.schemaVersionMissing,
  );
  if (schemaVersion != TutorProfileCodec.supportedSchemaVersion) {
    throw TutorProfileCodecException._(
      TutorProfileCodecErrorCode.schemaVersionUnknown,
      field: 'schemaVersion',
    );
  }
  final type = _requiredString(root, 'type');
  if (type != expectedType) {
    throw TutorProfileCodecException._(
      TutorProfileCodecErrorCode.documentTypeUnknown,
      field: 'type',
    );
  }
  return root;
}

ProfileField<String> _stringField(
  Map<String, Object?> root,
  String objectField,
  String field,
) {
  final value = _profileField(root, objectField, field);
  return ProfileField(
    _requiredString(value, 'value'),
    _provenance(value, field),
  );
}

ProfileField<List<String>> _stringsField(
  Map<String, Object?> root,
  String objectField,
  String field,
) {
  final value = _profileField(root, objectField, field);
  final strings = value['value'];
  if (strings is! List || strings.any((item) => item is! String)) {
    throw TutorProfileCodecException._(
      TutorProfileCodecErrorCode.fieldInvalid,
      field: field,
    );
  }
  return ProfileField(strings.cast<String>(), _provenance(value, field));
}

ProfileField<int?> _nullableIntField(
  Map<String, Object?> root,
  String objectField,
  String field,
) {
  final value = _profileField(root, objectField, field);
  final minutes = _requiredValue(value, 'value');
  if (minutes != null && minutes is! int) {
    throw TutorProfileCodecException._(
      TutorProfileCodecErrorCode.fieldInvalid,
      field: field,
    );
  }
  return ProfileField(minutes as int?, _provenance(value, field));
}

ProfileField<int> _intField(
  Map<String, Object?> root,
  String objectField,
  String field,
) {
  final value = _profileField(root, objectField, field);
  final integer = _requiredValue(value, 'value');
  if (integer is! int) {
    throw TutorProfileCodecException._(
      TutorProfileCodecErrorCode.fieldInvalid,
      field: field,
    );
  }
  return ProfileField(integer, _provenance(value, field));
}

ProfileField<bool> _boolField(
  Map<String, Object?> root,
  String objectField,
  String field,
) {
  final value = _profileField(root, objectField, field);
  final boolValue = _requiredValue(value, 'value');
  if (boolValue is! bool) {
    throw TutorProfileCodecException._(
      TutorProfileCodecErrorCode.fieldInvalid,
      field: field,
    );
  }
  return ProfileField(boolValue, _provenance(value, field));
}

ProfileField<T> _enumField<T extends Enum>(
  Map<String, Object?> root,
  String objectField,
  String field,
  List<T> values,
) {
  final value = _profileField(root, objectField, field);
  return ProfileField(
    _enumValue(_requiredString(value, 'value'), values, field),
    _provenance(value, field),
  );
}

Map<String, Object?> _profileField(
  Map<String, Object?> root,
  String objectField,
  String field,
) => _requiredObject(_requiredObject(root, objectField), field);

StudentProfileFieldProvenance _provenance(
  Map<String, Object?> field,
  String fieldName,
) => _enumValue(
  _requiredString(field, 'provenance'),
  StudentProfileFieldProvenance.values,
  '$fieldName.provenance',
);

T _enumValue<T extends Enum>(String name, List<T> values, String field) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  throw TutorProfileCodecException._(
    TutorProfileCodecErrorCode.enumUnknown,
    field: field,
  );
}

DateTime? _optionalUtcDeadline(Map<String, Object?> goal) {
  final value = _requiredValue(goal, 'deadline');
  if (value == null) return null;
  if (value is! String) {
    throw TutorProfileCodecException._(
      TutorProfileCodecErrorCode.deadlineInvalid,
      field: 'deadline',
    );
  }
  final parsed = DateTime.tryParse(value);
  if (!value.endsWith('Z') || parsed == null) {
    throw TutorProfileCodecException._(
      TutorProfileCodecErrorCode.deadlineInvalid,
      field: 'deadline',
    );
  }
  return parsed.toUtc();
}

Map<String, Object?> _asObjectMap(
  Object? value, [
  String code = TutorProfileCodecErrorCode.fieldInvalid,
]) {
  if (value is! Map) {
    throw TutorProfileCodecException._(code);
  }
  final mapped = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw TutorProfileCodecException._(code);
    }
    mapped[entry.key as String] = entry.value;
  }
  return mapped;
}

Map<String, Object?> _requiredObject(Map<String, Object?> map, String field) {
  if (!map.containsKey(field)) {
    throw TutorProfileCodecException._(
      TutorProfileCodecErrorCode.fieldMissing,
      field: field,
    );
  }
  final value = map[field];
  if (value is! Map) {
    throw TutorProfileCodecException._(
      TutorProfileCodecErrorCode.fieldInvalid,
      field: field,
    );
  }
  return _asObjectMap(value);
}

Object? _requiredValue(Map<String, Object?> map, String field) {
  if (!map.containsKey(field)) {
    throw TutorProfileCodecException._(
      TutorProfileCodecErrorCode.fieldMissing,
      field: field,
    );
  }
  return map[field];
}

String _requiredString(Map<String, Object?> map, String field) {
  final value = _requiredValue(map, field);
  if (value is! String) {
    throw TutorProfileCodecException._(
      TutorProfileCodecErrorCode.fieldInvalid,
      field: field,
    );
  }
  return value;
}

bool _requiredBool(Map<String, Object?> map, String field) {
  final value = _requiredValue(map, field);
  if (value is! bool) {
    throw TutorProfileCodecException._(
      TutorProfileCodecErrorCode.fieldInvalid,
      field: field,
    );
  }
  return value;
}

int _requiredInt(Map<String, Object?> map, String field, String missingCode) {
  final value = map[field];
  if (value is! int) {
    throw TutorProfileCodecException._(missingCode, field: field);
  }
  return value;
}
