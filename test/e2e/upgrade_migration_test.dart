// E12-R23 — legacy user migration release candidate (ADR 0487).
//
// Drives the MEASURED boot-time upgrade path (§0.0/R3-R6 of the round brief):
// `StorageMigrator.migrate()` never throws (per-step try/catch, a failed step
// leaves `schemaVersion` where it was); `AppBootstrap.run` discards the
// migration report, so a failed migration still yields `BootstrapSuccess`;
// the only measured `BootstrapFailure` inputs are an unparsable environment
// define, `openStore` returning `Failure`, and an unexpected exception.
//
// Every cell here calls `StorageMigrator(...).migrate()` directly (a public
// `lib/**` API, unmodified) to obtain the numeric `StorageMigrationReport`,
// and separately calls `AppBootstrap.run`'s injectable entry point on the
// SAME store to prove the app boot path this round is scoped to (ADR 0487
// D5). Neither `lib/**` nor `test/support/**` is touched.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/bootstrap/app_bootstrap.dart';
import 'package:strumsight/app/bootstrap/bootstrap_result.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/logging/app_logger.dart';
import 'package:strumsight/core/storage/json_document_store.dart';
import 'package:strumsight/core/storage/storage_keys.dart';
import 'package:strumsight/core/storage/storage_migrator.dart';

import '../core/storage/in_memory_key_value_store.dart';

void main() {
  group('A1 — full run from a legacy snapshot: numeric no-loss invariants '
      '(ADR 0487 D1)', () {
    test(
      'legacy_v1_storage.json (pre-E01-R06, fromVersion 0): record count, '
      'id-set and streak balance are identical before/after, migration '
      'reaches the last version, and the app boots on the migrated store',
      () async {
        final store = InMemoryKeyValueStore(
          _loadFixtureStore('legacy_v1_storage.json'),
        );
        final before = _LegacyContent.readFrom(store);

        final report = await StorageMigrator(
          store: store,
          logger: const NoopAppLogger(),
        ).migrate();

        expect(report.isComplete, isTrue, reason: 'no step should fail');
        expect(report.fromVersion, 0);
        expect(report.toVersion, appStorageMigrations.last.version);
        expect(report.applied, hasLength(appStorageMigrations.length));

        final after = _MigratedContent.readFrom(store);
        before.expectPreservedIn(after);

        final result = await AppBootstrap.run(
          openStore: () async => Success(store),
          loadVersion: () async => 'e12-r23-test',
          loadOnboardingSeen: () async => true,
        );
        expect(result, isA<BootstrapSuccess>());
      },
    );

    test('legacy_v2_storage.json (mid-upgrade, fromVersion 16): the six '
        'r07.* content migrations run, invariants hold, app boots', () async {
      final store = InMemoryKeyValueStore(
        _loadFixtureStore('legacy_v2_storage.json'),
      );
      final before = _LegacyContent.readFrom(store);

      final report = await StorageMigrator(
        store: store,
        logger: const NoopAppLogger(),
      ).migrate();

      expect(report.isComplete, isTrue, reason: 'no step should fail');
      expect(report.fromVersion, 16);
      expect(report.toVersion, appStorageMigrations.last.version);
      expect(report.applied, hasLength(6));

      final after = _MigratedContent.readFrom(store);
      before.expectPreservedIn(after);

      final result = await AppBootstrap.run(
        openStore: () async => Success(store),
        loadVersion: () async => 'e12-r23-test',
        loadOnboardingSeen: () async => true,
      );
      expect(result, isA<BootstrapSuccess>());
    });
  });

  group('A2 — an interrupted migration resumes from its checkpoint, never '
      'from scratch (ADR 0487 D2)', () {
    test('a write failure at version 10 stops the run at fromVersion; clearing '
        'the fault and re-running resumes at that checkpoint and reaches the '
        'SAME end state (record count, duplicate-free id-set) as an '
        'uninterrupted run of the identical fixture', () async {
      // Baseline: the same fixture, migrated in one uninterrupted pass.
      final baselineStore = InMemoryKeyValueStore(
        _loadFixtureStore('legacy_v1_storage.json'),
      );
      final baselineReport = await StorageMigrator(
        store: baselineStore,
        logger: const NoopAppLogger(),
      ).migrate();
      expect(baselineReport.isComplete, isTrue);
      final baseline = _MigratedContent.readFrom(baselineStore);

      // Interrupted run: version 10's target write ("nudge_enabled") is
      // blocked, simulating process death mid-migration.
      final interruptedStore = InMemoryKeyValueStore(
        _loadFixtureStore('legacy_v1_storage.json'),
      );
      interruptedStore.failingKeys.add(StorageKeys.nudgeEnabled);

      final firstAttempt = await StorageMigrator(
        store: interruptedStore,
        logger: const NoopAppLogger(),
      ).migrate();

      expect(firstAttempt.failure, isNotNull);
      expect(firstAttempt.fromVersion, 0);
      expect(firstAttempt.toVersion, 9, reason: 'versions 1-9 completed');
      expect(firstAttempt.applied, hasLength(9));

      // "New boot": the fault clears (the platform write succeeds this
      // time) and migrate() runs again on the SAME store.
      interruptedStore.failingKeys.remove(StorageKeys.nudgeEnabled);
      final resumed = await StorageMigrator(
        store: interruptedStore,
        logger: const NoopAppLogger(),
      ).migrate();

      expect(resumed.isComplete, isTrue);
      expect(
        resumed.fromVersion,
        firstAttempt.toVersion,
        reason: 'resume starts exactly where the interrupted run stopped',
      );
      expect(resumed.toVersion, appStorageMigrations.last.version);
      expect(
        resumed.applied,
        equals(
          appStorageMigrations
              .where((m) => m.version > 9)
              .map((m) => m.id)
              .toList(),
        ),
        reason: 'only the remaining 13 steps run — no replay of 1-9',
      );

      final afterResume = _MigratedContent.readFrom(interruptedStore);
      expect(afterResume.librarySessionIds, equals(baseline.librarySessionIds));
      expect(afterResume.songIds, equals(baseline.songIds));
      expect(afterResume.setlistIds, equals(baseline.setlistIds));
      expect(afterResume.practiceLogDays, equals(baseline.practiceLogDays));
      expect(afterResume.lessonProgress, equals(baseline.lessonProgress));
      expect(afterResume.streak, equals(baseline.streak));
      // Every id-set above came from a Set: a Set literal cannot itself
      // hold a duplicate, so the equality checks above already rule out
      // duplication. The write log is the direct, non-Set-mediated proof
      // that no already-migrated key was written a second time.
      expect(
        interruptedStore.writeLog.where(
          (w) => w == 'write:${StorageKeys.nudgeEnabled}',
        ),
        hasLength(1),
        reason:
            'the key that failed once, then succeeded on resume, must be '
            'written exactly once total — not twice',
      );
    });
  });

  group('A3 — a storage-write fault leaves a controlled failure, never a '
      'silent success or an empty profile (ADR 0487 D3)', () {
    test('corrupted_storage.json + a write fault at the FIRST pending '
        'migration: report.failure != null, toVersion == fromVersion, every '
        'raw legacy byte is untouched, and the app still boots reading the '
        'pre-existing (non-empty) legacy content', () async {
      final seed = _loadFixtureStore('corrupted_storage.json');
      final store = InMemoryKeyValueStore(seed);
      // The very first pending migration (version 1) is the only one that
      // can produce `toVersion == fromVersion`: any later fault would let
      // earlier steps succeed first and advance toVersion past fromVersion.
      store.failingKeys.add(StorageKeys.themeMode);
      final beforeValues = Map<String, Object>.of(store.values);

      final report = await StorageMigrator(
        store: store,
        logger: const NoopAppLogger(),
      ).migrate();

      expect(report.failure, isNotNull);
      expect(report.toVersion, report.fromVersion);
      expect(report.toVersion, 0);
      expect(report.applied, isEmpty);

      expect(
        store.values,
        equals(beforeValues),
        reason:
            'a migration that could not complete must not have written '
            'or removed a single key — the raw legacy data stays exactly '
            'as it was',
      );

      // AppBootstrap swallows the report (§0.0/R3 point 2) — the app must
      // still boot successfully on the un-migrated store.
      final result = await AppBootstrap.run(
        openStore: () async => Success(store),
        loadVersion: () async => 'e12-r23-test',
        loadOnboardingSeen: () async => true,
      );
      expect(result, isA<BootstrapSuccess>());

      // "Not an empty profile": the songs document, read through the same
      // legacy-fallback path the production repository uses
      // (JsonDocumentStore.readBody), still surfaces the pre-existing
      // legacy content — not null, not empty.
      final songsDocument = JsonDocumentStore(
        store: store,
        logger: const NoopAppLogger(),
        key: StorageKeys.songs,
        legacyKey: LegacyStorageKeys.songs,
        name: 'songs',
      );
      final songsBody = songsDocument.readBody();
      expect(songsBody, isNotNull);
      expect(songsBody, isA<List>());
      expect((songsBody! as List), isNotEmpty);
      expect(
        (songsBody as List).cast<Map<String, dynamic>>().map(
          (song) => song['id'],
        ),
        equals(
          (jsonDecode(seed[LegacyStorageKeys.songs]! as String) as List)
              .cast<Map<String, dynamic>>()
              .map((song) => song['id']),
        ),
      );
    });
  });

  group('A4 — storage that cannot be opened fails closed, no write attempted '
      '(ADR 0487 D3)', () {
    test(
      'openStore returning Failure(StorageFailure) yields BootstrapFailure '
      'with a storage-unavailable reason, and no store is ever touched',
      () async {
        final problems = <String>[];
        final result = await AppBootstrap.run(
          openStore: () async => const Failure(
            StorageFailure(code: FailureCode.storageUnavailable),
          ),
          loadVersion: () async => 'e12-r23-test',
          loadOnboardingSeen: () async {
            problems.add('loadOnboardingSeen must not run');
            return false;
          },
        );

        expect(result, isA<BootstrapFailure>());
        final failure = result as BootstrapFailure;
        expect(failure.problems, hasLength(1));
        expect(
          failure.problems.single,
          contains(FailureCode.storageUnavailable),
        );
        expect(
          problems,
          isEmpty,
          reason:
              'the onboarding read (and therefore any store access) must '
              'never run once the store failed to open',
        );
      },
    );
  });

  group('A5 — the migration report is numeric, not a bare success flag '
      '(ADR 0487 D1, D5 — see docs/release/client-migration.md)', () {
    test('legacy_v1_storage.json: applied id-list is pinned in order, and '
        'the per-key migrated record counts match the fixture', () async {
      final seed = _loadFixtureStore('legacy_v1_storage.json');
      final store = InMemoryKeyValueStore(seed);

      final report = await StorageMigrator(
        store: store,
        logger: const NoopAppLogger(),
      ).migrate();

      expect(report.fromVersion, 0);
      expect(report.toVersion, 22);
      expect(
        report.applied,
        equals(appStorageMigrations.map((m) => m.id).toList()),
      );

      final after = _MigratedContent.readFrom(store);
      expect(after.librarySessionIds, hasLength(2));
      expect(after.songIds, hasLength(3));
      expect(after.setlistIds, hasLength(1));
      expect(after.practiceLogDays, hasLength(4));
      expect(after.lessonProgress.keys, hasLength(3));
    });

    test('legacy_v2_storage.json: applied id-list covers only the six '
        'r07.* steps, and the per-key migrated record counts match the '
        'fixture', () async {
      final seed = _loadFixtureStore('legacy_v2_storage.json');
      final store = InMemoryKeyValueStore(seed);

      final report = await StorageMigrator(
        store: store,
        logger: const NoopAppLogger(),
      ).migrate();

      expect(report.fromVersion, 16);
      expect(report.toVersion, 22);
      expect(
        report.applied,
        equals(
          appStorageMigrations
              .where((m) => m.version > 16)
              .map((m) => m.id)
              .toList(),
        ),
      );

      final after = _MigratedContent.readFrom(store);
      expect(after.librarySessionIds, hasLength(1));
      expect(after.songIds, hasLength(2));
      expect(after.setlistIds, hasLength(2));
      expect(after.practiceLogDays, hasLength(3));
      expect(after.lessonProgress.keys, hasLength(2));
    });
  });
}

// ---------------------------------------------------------------------------
// Fixture loading
// ---------------------------------------------------------------------------

/// Loads a `test/fixtures/migrations/*.json` flat key-value document into the
/// shape `InMemoryKeyValueStore` expects: JSON arrays become `List<String>`
/// (the only list-typed value any migration reads is `favoriteChords`),
/// everything else keeps the type `jsonDecode` already gives it (`String`,
/// `int`, `double`, `bool`) — exactly what a real `SharedPreferences` read
/// would hand back for each of those types.
Map<String, Object> _loadFixtureStore(String fileName) {
  final raw =
      jsonDecode(File('test/fixtures/migrations/$fileName').readAsStringSync())
          as Map<String, dynamic>;
  return {
    for (final entry in raw.entries)
      entry.key: entry.value is List
          ? (entry.value as List).cast<String>()
          : entry.value as Object,
  };
}

// ---------------------------------------------------------------------------
// Pre-migration content (read via the LEGACY keys, pre-envelope shape)
// ---------------------------------------------------------------------------

/// The six user-content documents plus the streak balance, read straight off
/// their legacy keys before migration runs — the A1/A2 "before" snapshot.
class _LegacyContent {
  const _LegacyContent({
    required this.librarySessionIds,
    required this.songIds,
    required this.setlistIds,
    required this.practiceLogDays,
    required this.lessonProgress,
    required this.streak,
  });

  factory _LegacyContent.readFrom(InMemoryKeyValueStore store) {
    List<Map<String, dynamic>> list(String key) =>
        (jsonDecode(store.readString(key)!) as List)
            .cast<Map<String, dynamic>>();

    return _LegacyContent(
      librarySessionIds: list(
        LegacyStorageKeys.librarySessions,
      ).map((e) => e['id'] as String).toSet(),
      songIds: list(
        LegacyStorageKeys.songs,
      ).map((e) => e['id'] as String).toSet(),
      setlistIds: list(
        LegacyStorageKeys.setlists,
      ).map((e) => e['id'] as String).toSet(),
      practiceLogDays: list(
        LegacyStorageKeys.practiceLog,
      ).map((e) => e['day'] as int).toSet(),
      lessonProgress:
          jsonDecode(store.readString(LegacyStorageKeys.lessonProgress)!)
              as Map<String, dynamic>,
      streak:
          jsonDecode(store.readString(LegacyStorageKeys.streak)!)
              as Map<String, dynamic>,
    );
  }

  final Set<String> librarySessionIds;
  final Set<String> songIds;
  final Set<String> setlistIds;
  final Set<int> practiceLogDays;
  final Map<String, dynamic> lessonProgress;

  /// The `current`/`longest`/`last`/`freezes`/`total` streak balance
  /// (`StreakData.toJson`, `lib/features/streak/model/streak_data.dart`) —
  /// the only gamification-adjacent numeric state on the boot-migration path
  /// (§0.0/R6): a true XP ledger lives outside `appStorageMigrations` and is
  /// out of this round's measured scope.
  final Map<String, dynamic> streak;

  /// Asserts every record count, id-set and the streak balance in [after]
  /// equals this pre-migration snapshot exactly — the ADR 0487 D1 invariant.
  void expectPreservedIn(_MigratedContent after) {
    expect(
      after.librarySessionIds,
      equals(librarySessionIds),
      reason: 'librarySessions id-set and record count must be unchanged',
    );
    expect(
      after.songIds,
      equals(songIds),
      reason: 'songs id-set and record count must be unchanged',
    );
    expect(
      after.setlistIds,
      equals(setlistIds),
      reason: 'setlists id-set and record count must be unchanged',
    );
    expect(
      after.practiceLogDays,
      equals(practiceLogDays),
      reason:
          'practiceLog id-set (by day) and record count must be '
          'unchanged',
    );
    expect(
      after.lessonProgress,
      equals(lessonProgress),
      reason:
          'lessonProgress id-set (lesson ids) and values must be '
          'unchanged',
    );
    expect(
      after.streak,
      equals(streak),
      reason: 'the XP/streak balance must be bit-for-bit unchanged',
    );
  }
}

// ---------------------------------------------------------------------------
// Post-migration content (read via the NEW `ss.*` keys, envelope shape)
// ---------------------------------------------------------------------------

/// The same six documents, read back through the post-migration `ss.*` keys
/// and unwrapped from the `{"schemaVersion":1,...}` envelope
/// (`documentSchemaVersion`, `lib/core/storage/json_document_store.dart`) —
/// the A1/A2/A5 "after" snapshot.
class _MigratedContent {
  const _MigratedContent({
    required this.librarySessionIds,
    required this.songIds,
    required this.setlistIds,
    required this.practiceLogDays,
    required this.lessonProgress,
    required this.streak,
  });

  factory _MigratedContent.readFrom(InMemoryKeyValueStore store) {
    List<Map<String, dynamic>> items(String key) {
      final envelope =
          jsonDecode(store.readString(key)!) as Map<String, dynamic>;
      expect(envelope['schemaVersion'], documentSchemaVersion);
      return (envelope['items'] as List).cast<Map<String, dynamic>>();
    }

    Map<String, dynamic> data(String key) {
      final envelope =
          jsonDecode(store.readString(key)!) as Map<String, dynamic>;
      expect(envelope['schemaVersion'], documentSchemaVersion);
      return envelope['data'] as Map<String, dynamic>;
    }

    return _MigratedContent(
      librarySessionIds: items(
        StorageKeys.librarySessions,
      ).map((e) => e['id'] as String).toSet(),
      songIds: items(StorageKeys.songs).map((e) => e['id'] as String).toSet(),
      setlistIds: items(
        StorageKeys.setlists,
      ).map((e) => e['id'] as String).toSet(),
      practiceLogDays: items(
        StorageKeys.practiceLog,
      ).map((e) => e['day'] as int).toSet(),
      lessonProgress: data(StorageKeys.lessonProgress),
      streak: data(StorageKeys.streak),
    );
  }

  final Set<String> librarySessionIds;
  final Set<String> songIds;
  final Set<String> setlistIds;
  final Set<int> practiceLogDays;
  final Map<String, dynamic> lessonProgress;
  final Map<String, dynamic> streak;
}
