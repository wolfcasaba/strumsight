/// Current schema for persisted [QuestSchedule] records.
const int questScheduleSchemaVersion = 1;

/// The persisted time boundary of one generated daily or weekly quest.
final class QuestSchedule {
  QuestSchedule({
    required this.schemaVersion,
    required this.generationEpochDay,
    required this.timezoneOffsetMinutes,
    required this.catalogVersion,
    required DateTime expiresAt,
  }) : expiresAt = expiresAt.toUtc() {
    if (schemaVersion != questScheduleSchemaVersion) {
      throw ArgumentError.value(
        schemaVersion,
        'schemaVersion',
        'is not supported',
      );
    }
    if (timezoneOffsetMinutes < -840 || timezoneOffsetMinutes > 840) {
      throw ArgumentError.value(
        timezoneOffsetMinutes,
        'timezoneOffsetMinutes',
        'must be within the UTC offset range',
      );
    }
    if (catalogVersion < 1) {
      throw ArgumentError.value(
        catalogVersion,
        'catalogVersion',
        'must be positive',
      );
    }
  }

  final int schemaVersion;
  final int generationEpochDay;
  final int timezoneOffsetMinutes;
  final int catalogVersion;
  final DateTime expiresAt;

  /// The quest is active until, but not including, [expiresAt].
  bool isActiveAt(DateTime now) => now.toUtc().isBefore(expiresAt);

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'generationEpochDay': generationEpochDay,
    'timezoneOffsetMinutes': timezoneOffsetMinutes,
    'catalogVersion': catalogVersion,
    'expiresAt': expiresAt.toIso8601String(),
  };

  factory QuestSchedule.fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      throw ArgumentError.value(json, 'json', 'must be an object');
    }
    final expiryValue = json['expiresAt'];
    final expiresAt = expiryValue is String
        ? DateTime.tryParse(expiryValue)
        : null;
    if (expiresAt == null || !expiresAt.isUtc) {
      throw ArgumentError.value(
        expiryValue,
        'expiresAt',
        'must be a UTC ISO date',
      );
    }
    return QuestSchedule(
      schemaVersion: _requireInt(json, 'schemaVersion'),
      generationEpochDay: _requireInt(json, 'generationEpochDay'),
      timezoneOffsetMinutes: _requireInt(json, 'timezoneOffsetMinutes'),
      catalogVersion: _requireInt(json, 'catalogVersion'),
      expiresAt: expiresAt,
    );
  }
}

int _requireInt(Map<String, Object?> object, String field) {
  final value = object[field];
  if (value is int) return value;
  throw ArgumentError.value(value, field, 'must be an integer');
}
