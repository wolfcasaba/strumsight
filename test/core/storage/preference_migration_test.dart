import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/logging/app_logger.dart';
import 'package:strumsight/core/storage/storage_keys.dart';
import 'package:strumsight/core/storage/storage_migrator.dart';

import 'in_memory_key_value_store.dart';

/// E01-R06 §6.3 — the preference keys shipped builds wrote must survive the
/// move to the `ss.` catalogue. A user who updates the app keeps their theme,
/// capo, tuning, calibration and onboarding state; nothing silently resets.
void main() {
  /// Every legacy → new pair this round migrates, with a representative value.
  final legacyValues = <String, ({String to, Object value})>{
    LegacyStorageKeys.themeMode: (to: StorageKeys.themeMode, value: 'light'),
    LegacyStorageKeys.locale: (to: StorageKeys.locale, value: 'hu'),
    LegacyStorageKeys.confidenceThreshold: (
      to: StorageKeys.confidenceThreshold,
      value: 0.72,
    ),
    LegacyStorageKeys.capoFret: (to: StorageKeys.capoFret, value: 3),
    LegacyStorageKeys.tuningA4: (to: StorageKeys.tuningA4, value: 442),
    LegacyStorageKeys.leftHanded: (to: StorageKeys.leftHanded, value: true),
    LegacyStorageKeys.inputLatencyMs: (
      to: StorageKeys.inputLatencyMs,
      value: -40,
    ),
    LegacyStorageKeys.visualLatencyMs: (
      to: StorageKeys.visualLatencyMs,
      value: 25,
    ),
    LegacyStorageKeys.labMode: (to: StorageKeys.labMode, value: true),
    LegacyStorageKeys.nudgeEnabled: (to: StorageKeys.nudgeEnabled, value: true),
    LegacyStorageKeys.onboardingSeen: (
      to: StorageKeys.onboardingSeen,
      value: true,
    ),
    LegacyStorageKeys.tunerTuning: (
      to: StorageKeys.tunerTuning,
      value: 'drop_d',
    ),
    LegacyStorageKeys.favoriteChords: (
      to: StorageKeys.favoriteChords,
      value: <String>['Am', 'C'],
    ),
    LegacyStorageKeys.metronomeMuted: (
      to: StorageKeys.metronomeMuted,
      value: true,
    ),
    LegacyStorageKeys.practiceSpeed: (
      to: StorageKeys.practiceSpeed,
      value: 0.75,
    ),
    LegacyStorageKeys.dailyGoalMinutes: (
      to: StorageKeys.dailyGoalMinutes,
      value: 20,
    ),
  };

  /// E01-R07 §7.3 — the six user-content documents. The value is the legacy
  /// blob exactly as a shipped build wrote it (a bare array / object).
  final legacyDocuments = <String, ({String to, String body, String bodyKey})>{
    LegacyStorageKeys.librarySessions: (
      to: StorageKeys.librarySessions,
      body: '[]',
      bodyKey: 'items',
    ),
    LegacyStorageKeys.songs: (
      to: StorageKeys.songs,
      body:
          '[{"id":"s1","name":"Riff","chords":["C"],"pat":"d-------",'
          '"bpm":90,"bpb":4}]',
      bodyKey: 'items',
    ),
    LegacyStorageKeys.setlists: (
      to: StorageKeys.setlists,
      body: '[{"id":"l1","name":"Gig","songs":["s1"]}]',
      bodyKey: 'items',
    ),
    LegacyStorageKeys.practiceLog: (
      to: StorageKeys.practiceLog,
      body: '[{"day":20643,"src":"live","sec":60,"str":8,"chd":3}]',
      bodyKey: 'items',
    ),
    LegacyStorageKeys.lessonProgress: (
      to: StorageKeys.lessonProgress,
      body: '{"lesson-1":0.9}',
      bodyKey: 'data',
    ),
    LegacyStorageKeys.streak: (
      to: StorageKeys.streak,
      body: '{"current":7,"longest":9,"last":20643,"freezes":1,"total":11}',
      bodyKey: 'data',
    ),
  };

  test('every migrated preference has exactly one migration', () {
    final versions = appStorageMigrations.map((m) => m.version).toList();
    expect(
      versions,
      List.generate(appStorageMigrations.length, (i) => i + 1),
      reason: 'versions must be 1..n, in order, with no gaps or duplicates',
    );
    expect(
      appStorageMigrations.map((m) => m.id).toSet().length,
      appStorageMigrations.length,
      reason: 'a migration id is a stable log identifier and is never reused',
    );
    expect(
      appStorageMigrations.length,
      legacyValues.length + legacyDocuments.length,
      reason: 'each migrated key — preference or document — has one migration',
    );
  });

  test('a returning user keeps every stored document, wrapped', () async {
    final store = InMemoryKeyValueStore({
      for (final entry in legacyDocuments.entries) entry.key: entry.value.body,
    });

    final report = await StorageMigrator(
      store: store,
      logger: const NoopAppLogger(),
    ).migrate();

    expect(report.isComplete, isTrue);
    for (final entry in legacyDocuments.entries) {
      final raw = store.readString(entry.value.to);
      expect(raw, isNotNull, reason: '${entry.key} must arrive at its new key');
      final decoded = jsonDecode(raw!) as Map<String, dynamic>;
      expect(decoded['schemaVersion'], 1, reason: 'the §7.3 envelope');
      expect(
        decoded[entry.value.bodyKey],
        jsonDecode(entry.value.body),
        reason: 'the user content itself is carried over verbatim',
      );
      expect(
        store.contains(entry.key),
        isFalse,
        reason: 'the legacy key is removed once the new one is written',
      );
    }
  });

  test('an unparsable document is left where it is, never deleted', () async {
    final store = InMemoryKeyValueStore({
      LegacyStorageKeys.songs: 'not json at all',
    });

    final report = await StorageMigrator(
      store: store,
      logger: const NoopAppLogger(),
    ).migrate();

    expect(report.isComplete, isTrue, reason: 'a bad blob must not block boot');
    expect(
      store.readString(LegacyStorageKeys.songs),
      'not json at all',
      reason: 'the bytes stay for the document store to quarantine',
    );
    expect(store.contains(StorageKeys.songs), isFalse);
  });

  test('an already-migrated document is never overwritten', () async {
    final migrated = jsonEncode({
      'schemaVersion': 1,
      'items': [
        {'id': 'l1', 'name': 'New', 'songs': <String>[]},
      ],
    });
    // The shape after a run that died between the write and the removal.
    final store = InMemoryKeyValueStore({
      StorageKeys.setlists: migrated,
      LegacyStorageKeys.setlists: '[{"id":"l0","name":"Stale","songs":[]}]',
    });

    await StorageMigrator(
      store: store,
      logger: const NoopAppLogger(),
    ).migrate();

    expect(store.readString(StorageKeys.setlists), migrated);
    expect(store.contains(LegacyStorageKeys.setlists), isFalse);
  });

  test('a returning user keeps every stored preference', () async {
    final store = InMemoryKeyValueStore({
      for (final entry in legacyValues.entries) entry.key: entry.value.value,
    });

    final report = await StorageMigrator(
      store: store,
      logger: const NoopAppLogger(),
    ).migrate();

    expect(report.isComplete, isTrue);
    expect(report.fromVersion, 0);
    expect(report.toVersion, appStorageMigrations.length);

    for (final entry in legacyValues.entries) {
      expect(
        store.values[entry.value.to],
        entry.value.value,
        reason: '${entry.key} must arrive at ${entry.value.to} unchanged',
      );
      expect(
        store.contains(entry.key),
        isFalse,
        reason: 'the legacy key is removed once the new one is written',
      );
    }
  });

  test('a second run is a no-op (idempotent)', () async {
    final store = InMemoryKeyValueStore({
      for (final entry in legacyValues.entries) entry.key: entry.value.value,
    });
    await StorageMigrator(
      store: store,
      logger: const NoopAppLogger(),
    ).migrate();
    store.writeLog.clear();

    final second = await StorageMigrator(
      store: store,
      logger: const NoopAppLogger(),
    ).migrate();

    expect(second.applied, isEmpty);
    expect(
      store.writeLog,
      isEmpty,
      reason: 'nothing left to do → not a single write',
    );
    expect(store.values[StorageKeys.capoFret], 3);
  });

  test('an interrupted run resumes where it stopped', () async {
    // Simulate a process death after the first three migrations: their values
    // moved and the schema version records it.
    final store = InMemoryKeyValueStore({
      StorageKeys.schemaVersion: 3,
      StorageKeys.themeMode: 'light',
      StorageKeys.locale: 'hu',
      StorageKeys.confidenceThreshold: 0.72,
      LegacyStorageKeys.capoFret: 3,
      LegacyStorageKeys.tuningA4: 442,
    });

    final report = await StorageMigrator(
      store: store,
      logger: const NoopAppLogger(),
    ).migrate();

    expect(report.fromVersion, 3);
    expect(report.applied.first, 'r06.capo_fret');
    expect(store.values[StorageKeys.capoFret], 3);
    expect(store.values[StorageKeys.tuningA4], 442);
    expect(
      store.values[StorageKeys.themeMode],
      'light',
      reason: 'an already-migrated value is not touched again',
    );
  });

  test('a value stored under the wrong type is kept, not deleted', () async {
    // A build that wrote the capo as a String: unreadable as an int. The
    // migration must not destroy it — the feature falls back to its default.
    final store = InMemoryKeyValueStore({LegacyStorageKeys.capoFret: '3'});

    final report = await StorageMigrator(
      store: store,
      logger: const NoopAppLogger(),
    ).migrate();

    expect(report.isComplete, isTrue);
    expect(store.values[LegacyStorageKeys.capoFret], '3');
    expect(store.contains(StorageKeys.capoFret), isFalse);
  });

  test('a rejected write stops the run and keeps the schema version', () async {
    final store = InMemoryKeyValueStore({
      LegacyStorageKeys.themeMode: 'light',
      LegacyStorageKeys.locale: 'hu',
    })..failingKeys.add(StorageKeys.locale);

    final report = await StorageMigrator(
      store: store,
      logger: const NoopAppLogger(),
    ).migrate();

    expect(report.isComplete, isFalse);
    expect(report.applied, ['r06.theme_mode']);
    expect(
      store.values[StorageKeys.schemaVersion],
      1,
      reason: 'the failed step is retried on the next boot',
    );
    expect(
      store.values[LegacyStorageKeys.locale],
      'hu',
      reason: 'the source value survives a failed migration',
    );
  });
}
