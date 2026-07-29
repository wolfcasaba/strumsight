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
    expect(appStorageMigrations.length, legacyValues.length);
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
