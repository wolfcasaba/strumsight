import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/logging/app_logger.dart';
import 'package:strumsight/core/storage/key_value_store.dart';
import 'package:strumsight/core/storage/storage_keys.dart';
import 'package:strumsight/core/storage/storage_migrator.dart';

import 'in_memory_key_value_store.dart';

// E01-R05 §5.3 — the migrator must be idempotent, resumable and
// non-destructive: user data is never deleted before the new write is
// confirmed, a corrupt value never crashes the app, and a failed step is
// retried on the next boot instead of being skipped.

class _RecordingLogger implements AppLogger {
  final List<String> events = [];

  @override
  void debug(String event, {Map<String, Object?> fields = const {}}) =>
      events.add('debug:$event');

  @override
  void info(String event, {Map<String, Object?> fields = const {}}) =>
      events.add('info:$event');

  @override
  void warning(
    String event, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> fields = const {},
  }) => events.add('warning:$event');

  @override
  void error(
    String event, {
    required Object error,
    required StackTrace stackTrace,
    Map<String, Object?> fields = const {},
  }) => events.add('error:$event');
}

/// A migration that has to parse what it moves — the case where a corrupt
/// value is a real hazard (Library sessions, songs, practice log are JSON).
class _JsonRewriteMigration implements StorageMigration {
  const _JsonRewriteMigration({required this.from, required this.to});

  @override
  int get version => 1;

  @override
  String get id => 'json-rewrite';

  final String from;
  final String to;

  @override
  Future<void> apply(KeyValueStore store, AppLogger logger) async {
    final raw = store.readString(from);
    if (raw == null) return;
    final decoded = jsonDecode(raw) as List<dynamic>; // throws if corrupt
    await store.writeString(to, jsonEncode(decoded.reversed.toList()));
    await store.remove(from);
  }
}

void main() {
  late InMemoryKeyValueStore store;
  late _RecordingLogger logger;

  setUp(() {
    store = InMemoryKeyValueStore();
    logger = _RecordingLogger();
  });

  Future<StorageMigrationReport> run(List<StorageMigration> migrations) =>
      StorageMigrator(
        store: store,
        logger: logger,
        migrations: migrations,
      ).migrate();

  const rename = RenameKeyMigration.string(
    version: 1,
    id: 'theme-mode',
    from: LegacyStorageKeys.themeMode,
    to: StorageKeys.themeMode,
  );

  group('schema version', () {
    test('no migrations → nothing written, version stays 0', () async {
      final report = await run(const []);
      expect(report.fromVersion, 0);
      expect(report.toVersion, 0);
      expect(report.applied, isEmpty);
      expect(store.contains(StorageKeys.schemaVersion), isFalse);
      expect(store.writeLog, isEmpty);
    });

    test('the shipped migration list is forward-only and starts at 1 '
        '(a key is renamed in the round that moves its owner)', () {
      // What each shipped migration DOES is covered by
      // `preference_migration_test.dart`; this pins the list's shape.
      expect(appStorageMigrations, isNotEmpty);
      expect(appStorageMigrations.first.version, 1);
      expect(
        appStorageMigrations.map((m) => m.version).toList()..sort(),
        appStorageMigrations.map((m) => m.version).toList(),
        reason: 'the list is stored in version order',
      );
    });

    test('an already-current store runs nothing', () async {
      store.values[StorageKeys.schemaVersion] = 1;
      store.values[LegacyStorageKeys.themeMode] = 'dark';
      final report = await run(const [rename]);

      expect(report.applied, isEmpty);
      // The legacy value is untouched: this store is *past* that migration.
      expect(store.values[LegacyStorageKeys.themeMode], 'dark');
    });

    test('the version is written after each migration, so an interrupted '
        'run resumes at the next pending step', () async {
      await run(const [
        rename,
        RenameKeyMigration.integer(
          version: 2,
          id: 'capo',
          from: LegacyStorageKeys.capoFret,
          to: StorageKeys.capoFret,
        ),
      ]);
      expect(store.readInt(StorageKeys.schemaVersion), 2);
    });
  });

  group('RenameKeyMigration', () {
    test('moves the value and removes the old key', () async {
      store.values[LegacyStorageKeys.themeMode] = 'dark';
      final report = await run(const [rename]);

      expect(report.applied, ['theme-mode']);
      expect(store.readString(StorageKeys.themeMode), 'dark');
      expect(store.contains(LegacyStorageKeys.themeMode), isFalse);
      // Order matters: the new key is written BEFORE the old one is dropped.
      expect(store.writeLog, [
        'write:${StorageKeys.themeMode}',
        'remove:${LegacyStorageKeys.themeMode}',
        'write:${StorageKeys.schemaVersion}',
      ]);
    });

    test('every primitive kind migrates', () async {
      store.values
        ..[LegacyStorageKeys.leftHanded] = true
        ..[LegacyStorageKeys.capoFret] = 3
        ..[LegacyStorageKeys.confidenceThreshold] = 0.42
        ..[LegacyStorageKeys.favoriteChords] = ['C', 'G'];

      await run(const [
        RenameKeyMigration.boolean(
          version: 1,
          id: 'left-handed',
          from: LegacyStorageKeys.leftHanded,
          to: StorageKeys.leftHanded,
        ),
        RenameKeyMigration.integer(
          version: 2,
          id: 'capo',
          from: LegacyStorageKeys.capoFret,
          to: StorageKeys.capoFret,
        ),
        RenameKeyMigration.number(
          version: 3,
          id: 'threshold',
          from: LegacyStorageKeys.confidenceThreshold,
          to: StorageKeys.confidenceThreshold,
        ),
        RenameKeyMigration.stringList(
          version: 4,
          id: 'favorites',
          from: LegacyStorageKeys.favoriteChords,
          to: StorageKeys.favoriteChords,
        ),
      ]);

      expect(store.readBool(StorageKeys.leftHanded), isTrue);
      expect(store.readInt(StorageKeys.capoFret), 3);
      expect(store.readDouble(StorageKeys.confidenceThreshold), 0.42);
      expect(store.readStringList(StorageKeys.favoriteChords), ['C', 'G']);
    });

    test('running the same migration twice is a no-op the second time '
        '(idempotent)', () async {
      store.values[LegacyStorageKeys.themeMode] = 'light';
      await run(const [rename]);

      // Second boot: pretend the version was lost so the step runs again.
      await store.remove(StorageKeys.schemaVersion);
      store.writeLog.clear();
      final second = await run(const [rename]);

      expect(second.applied, ['theme-mode']);
      expect(store.readString(StorageKeys.themeMode), 'light');
      expect(store.writeLog, ['write:${StorageKeys.schemaVersion}']);
    });

    test('a run interrupted between write and remove finishes the cleanup '
        'without clobbering the new value', () async {
      store.values
        ..[LegacyStorageKeys.themeMode] =
            'dark' // stale leftover
        ..[StorageKeys.themeMode] = 'light'; // already migrated + user changed

      await run(const [rename]);

      expect(store.readString(StorageKeys.themeMode), 'light');
      expect(store.contains(LegacyStorageKeys.themeMode), isFalse);
    });

    test('a value present but unreadable as this type is logged and kept, '
        'not deleted', () async {
      store.values[LegacyStorageKeys.themeMode] = 42; // wrong type
      final report = await run(const [rename]);

      expect(report.isComplete, isTrue); // the app boots
      expect(
        logger.events,
        contains('warning:storage.migration.unreadable_value'),
      );
      expect(store.values[LegacyStorageKeys.themeMode], 42); // preserved
      expect(store.contains(StorageKeys.themeMode), isFalse);
    });

    test('a failing write aborts the run and keeps the old key', () async {
      store.values[LegacyStorageKeys.themeMode] = 'dark';
      store.failingKeys.add(StorageKeys.themeMode);

      final report = await run(const [rename]);

      expect(report.isComplete, isFalse);
      expect(report.failure, isA<StorageFailure>());
      expect(report.toVersion, 0); // not advanced → retried next boot
      expect(store.values[LegacyStorageKeys.themeMode], 'dark');
      expect(logger.events, contains('error:storage.migration.failed'));
    });
  });

  group('corrupt data', () {
    test('corrupt JSON does not crash the app; it is logged and the data '
        'is preserved for a later attempt', () async {
      store.values[LegacyStorageKeys.librarySessions] = '{not json';

      final report = await run(const [
        _JsonRewriteMigration(
          from: LegacyStorageKeys.librarySessions,
          to: StorageKeys.librarySessions,
        ),
      ]);

      expect(report.isComplete, isFalse);
      expect(logger.events, contains('error:storage.migration.failed'));
      expect(store.values[LegacyStorageKeys.librarySessions], '{not json');
      expect(store.contains(StorageKeys.schemaVersion), isFalse);
    });

    test(
      'a later migration is not skipped when an earlier one fails',
      () async {
        store.values
          ..[LegacyStorageKeys.librarySessions] = '{not json'
          ..[LegacyStorageKeys.capoFret] = 4;

        await run(const [
          _JsonRewriteMigration(
            from: LegacyStorageKeys.librarySessions,
            to: StorageKeys.librarySessions,
          ),
          RenameKeyMigration.integer(
            version: 2,
            id: 'capo',
            from: LegacyStorageKeys.capoFret,
            to: StorageKeys.capoFret,
          ),
        ]);

        // Version stayed at 0, so the next boot retries BOTH — the second
        // migration is pending, never silently passed over.
        expect(store.contains(StorageKeys.schemaVersion), isFalse);
        expect(store.values[LegacyStorageKeys.capoFret], 4);
      },
    );

    test('valid JSON migrates through the same path', () async {
      store.values[LegacyStorageKeys.librarySessions] = jsonEncode([1, 2, 3]);

      final report = await run(const [
        _JsonRewriteMigration(
          from: LegacyStorageKeys.librarySessions,
          to: StorageKeys.librarySessions,
        ),
      ]);

      expect(report.isComplete, isTrue);
      expect(
        store.readString(StorageKeys.librarySessions),
        jsonEncode([3, 2, 1]),
      );
      expect(store.contains(LegacyStorageKeys.librarySessions), isFalse);
    });
  });
}
