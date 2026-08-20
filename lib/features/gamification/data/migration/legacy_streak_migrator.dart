import 'dart:convert';

import 'package:strumsight/core/storage/json_document_store.dart';
import 'package:strumsight/core/storage/key_value_store.dart';
import 'package:strumsight/core/storage/storage_keys.dart';
import 'package:strumsight/features/gamification/domain/streak/streak_state.dart';

/// Read-only adapter from the shipping legacy streak documents to Streak V2.
final class LegacyStreakMigrator {
  const LegacyStreakMigrator(this._store);

  final KeyValueStore _store;

  /// Reads the namespaced envelope first, then the pre-namespace raw JSON.
  ///
  /// The source documents are never written or removed. A present but malformed
  /// or future-version envelope is rejected instead of being treated as empty.
  StreakState? migrate() {
    final namespaced = _store.readString(StorageKeys.streak);
    if (namespaced != null) return _fromEnvelope(namespaced);
    if (_store.contains(StorageKeys.streak)) {
      throw const FormatException(
        'The namespaced legacy streak is not JSON text.',
      );
    }

    final rawLegacy = _store.readString(LegacyStorageKeys.streak);
    if (rawLegacy != null) return _fromRawLegacy(rawLegacy);
    if (_store.contains(LegacyStorageKeys.streak)) {
      throw const FormatException('The raw legacy streak is not JSON text.');
    }
    return null;
  }

  StreakState _fromEnvelope(String source) {
    final envelope = _decodeObject(source, 'namespaced envelope');
    final version = envelope['schemaVersion'];
    if (version is! int || version > documentSchemaVersion) {
      throw const FormatException(
        'The legacy streak envelope version is unsupported.',
      );
    }
    return _fromLegacyBody(_requireObject(envelope['data'], 'envelope data'));
  }

  StreakState _fromRawLegacy(String source) =>
      _fromLegacyBody(_decodeObject(source, 'raw legacy streak'));

  StreakState _fromLegacyBody(Map<String, dynamic> source) => StreakState(
    current: _requireCounter(source, 'current'),
    longest: _requireCounter(source, 'longest'),
    lastQualifiedDay: _requireLastDay(source),
    freezes: _requireCounter(source, 'freezes'),
    totalQualifiedDays: _requireCounter(source, 'total'),
  );
}

Map<String, dynamic> _decodeObject(String source, String label) {
  try {
    return _requireObject(jsonDecode(source), label);
  } on FormatException {
    rethrow;
  } on Object {
    throw FormatException('The $label is malformed.');
  }
}

Map<String, dynamic> _requireObject(Object? value, String label) {
  if (value is Map<String, dynamic>) return value;
  throw FormatException('The $label must be a JSON object.');
}

int _requireCounter(Map<String, dynamic> source, String key) {
  final value = source[key];
  if (value is! int || value < 0) {
    throw FormatException('The legacy streak $key counter is invalid.');
  }
  return value;
}

int _requireLastDay(Map<String, dynamic> source) {
  final value = source['last'];
  if (value is! int || value < -1) {
    throw const FormatException('The legacy streak last day is invalid.');
  }
  return value;
}
