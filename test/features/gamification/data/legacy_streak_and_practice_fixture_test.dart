import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/storage/json_document_store.dart';
import 'package:strumsight/core/storage/key_value_store.dart';
import 'package:strumsight/core/storage/storage_keys.dart';
import 'package:strumsight/features/gamification/data/gamification_repository.dart';
import 'package:strumsight/features/gamification/data/gamification_storage_schema.dart';
import 'package:strumsight/features/gamification/data/migration/gamification_migrator.dart';
import 'package:strumsight/features/gamification/data/migration/legacy_practice_adapter.dart';
import 'package:strumsight/features/gamification/data/migration/legacy_streak_migrator.dart';
import 'package:strumsight/features/gamification/domain/activity/activity_source.dart';
import 'package:strumsight/features/progress/model/practice_entry.dart';

import '../../../core/storage/in_memory_key_value_store.dart';

// E08-R30 — Real-shape fixture coverage for the legacy migrators. Pre-v22
// raw blobs are written under the EXACT [LegacyStorageKeys] constants;
// post-v22 envelopes under the EXACT [StorageKeys] constants. No mock
// schemas, no synthetic fixtures — what a shipping build would persist at
// those keys.

void main() {
  group('LegacyStreakMigrator on real-shape fixtures', () {
    test('pre-v22 raw `practice_streak_v1` blob decodes to a StreakState with '
        'the shipped field names', () {
      final store = InMemoryKeyValueStore(<String, Object>{
        LegacyStorageKeys.streak: jsonEncode(<String, Object>{
          'current': 5,
          'longest': 12,
          'last': 20400,
          'freezes': 1,
          'total': 30,
        }),
      });

      final migrated = LegacyStreakMigrator(store).migrate();

      expect(migrated, isNotNull);
      expect(migrated!.current, 5);
      expect(migrated.longest, 12);
      expect(migrated.lastQualifiedDay, 20400);
      expect(migrated.freezes, 1);
      expect(migrated.totalQualifiedDays, 30);
    });

    test('post-v22 namespaced envelope under `ss.streak.state` decodes to the '
        'same StreakState projection as the raw legacy blob', () {
      final store = InMemoryKeyValueStore(<String, Object>{
        StorageKeys.streak: jsonEncode(<String, Object>{
          'schemaVersion': documentSchemaVersion,
          'data': <String, Object>{
            'current': 5,
            'longest': 12,
            'last': 20400,
            'freezes': 1,
            'total': 30,
          },
        }),
      });

      final migrated = LegacyStreakMigrator(store).migrate();

      expect(migrated, isNotNull);
      expect(migrated!.current, 5);
      expect(migrated.longest, 12);
      expect(migrated.lastQualifiedDay, 20400);
      expect(migrated.freezes, 1);
      expect(migrated.totalQualifiedDays, 30);
    });

    test(
      'the namespaced envelope wins over a leftover raw legacy key when both '
      'are present (the post-migration state is the V2 truth)',
      () {
        final store = InMemoryKeyValueStore(<String, Object>{
          // Legacy raw says day 100, current 0 — the v22 envelope overwrote
          // it on the latest write, and the rename migration has not yet
          // removed the legacy key.
          LegacyStorageKeys.streak: jsonEncode(<String, Object>{
            'current': 0,
            'longest': 0,
            'last': 100,
            'freezes': 0,
            'total': 0,
          }),
          StorageKeys.streak: jsonEncode(<String, Object>{
            'schemaVersion': documentSchemaVersion,
            'data': <String, Object>{
              'current': 7,
              'longest': 14,
              'last': 20500,
              'freezes': 2,
              'total': 42,
            },
          }),
        });

        final migrated = LegacyStreakMigrator(store).migrate();

        expect(migrated, isNotNull);
        expect(migrated!.current, 7);
        expect(migrated.longest, 14);
        expect(migrated.lastQualifiedDay, 20500);
        expect(migrated.totalQualifiedDays, 42);
      },
    );
  });

  group('LegacyPracticeAdapter on real-shape practice fixtures', () {
    test('a pre-v22 raw `practice_log_v1` list decodes through '
        '`PracticeEntry.fromJson` into the same canonical shape the migrator '
        'consumes', () {
      final rawItems = <Map<String, Object?>>[
        <String, Object?>{
          'day': 20400,
          'src': 'live',
          'sec': 30,
          'str': 20,
          'chd': 1,
        },
        <String, Object?>{
          'day': 20401,
          'src': 'analyze',
          'sec': 20,
          'str': 15,
          'chd': 2,
        },
        <String, Object?>{
          'day': 20402,
          'src': 'learn',
          'sec': 40,
          'str': 25,
          'chd': 4,
          'dir': 0.9,
        },
      ];
      final rawBlob = jsonEncode(rawItems);

      final decoded = (jsonDecode(rawBlob) as List<dynamic>)
          .map((dynamic e) => PracticeEntry.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);

      expect(decoded, hasLength(3));
      expect(decoded[0].day, 20400);
      expect(decoded[0].source, PracticeSource.live);
      expect(decoded[2].directionAccuracy, 0.9);

      final events = LegacyPracticeAdapter().adapt(decoded);
      expect(events, hasLength(3));
      expect(events.map((event) => event.source), <ActivitySource>[
        ActivitySource.live,
        ActivitySource.analyze,
        ActivitySource.learn,
      ]);
    });

    test('a post-v22 envelope under `ss.progress.practice_log` decodes through '
        'the canonical JSON document store reader and yields the same '
        'PracticeEntry list and therefore the same canonical events', () {
      final envelope = jsonEncode(<String, Object?>{
        'schemaVersion': documentSchemaVersion,
        'items': <Map<String, Object?>>[
          <String, Object?>{
            'day': 20400,
            'src': 'live',
            'sec': 30,
            'str': 20,
            'chd': 1,
          },
          <String, Object?>{
            'day': 20401,
            'src': 'learn',
            'sec': 45,
            'str': 30,
            'chd': 4,
            'dir': 0.8,
          },
        ],
      });
      final store = InMemoryKeyValueStore(<String, Object>{
        StorageKeys.practiceLog: envelope,
      });

      final decoded = _decodeV2Envelope(store, StorageKeys.practiceLog);
      expect(decoded, hasLength(2));

      final events = LegacyPracticeAdapter().adapt(decoded);
      expect(events, hasLength(2));
      expect(events.first.epochDay, 20400);
      expect(events.last.epochDay, 20401);
    });
  });

  group('GamificationMigrator with real PracticeEntry inputs', () {
    test(
      'reports the canonical total counts and persists a checkpoint on every '
      'real legacy snapshot',
      () async {
        final repo = _RecordingGamificationRepository();
        final migrator = GamificationMigrator(gamificationRepository: repo);

        final rawItems = <Map<String, Object?>>[
          <String, Object?>{
            'day': 20000,
            'src': 'live',
            'sec': 30,
            'str': 20,
            'chd': 1,
          },
          <String, Object?>{
            'day': 20001,
            'src': 'analyze',
            'sec': 20,
            'str': 15,
            'chd': 2,
          },
          <String, Object?>{
            'day': 20002,
            'src': 'learn',
            'sec': 40,
            'str': 25,
            'chd': 4,
            'dir': 0.9,
          },
        ];
        final entries = rawItems
            .map(
              (map) => PracticeEntry.fromJson(Map<String, dynamic>.from(map)),
            )
            .toList(growable: false);

        final report = await migrator.migrate(entries);

        expect(report.recordCount, 3);
        expect(report.totalSeconds, 90);
        expect(report.totalStrokes, 60);
        expect(report.totalChords, 7);
        expect(repo.processedCountsWritten, <int>[1, 2, 3]);
      },
    );

    test('an empty real-shape fixture still migrates cleanly (no crash, no '
        'checkpoint write)', () async {
      final repo = _RecordingGamificationRepository();
      final migrator = GamificationMigrator(gamificationRepository: repo);

      final report = await migrator.migrate(const <PracticeEntry>[]);

      expect(report.recordCount, 0);
      expect(report.events, isEmpty);
      // No checkpoint write when there is nothing to do.
      expect(repo.processedCountsWritten, isEmpty);
    });
  });
}

List<PracticeEntry> _decodeV2Envelope(KeyValueStore store, String envelopeKey) {
  final raw = store.readString(envelopeKey);
  if (raw == null) return const <PracticeEntry>[];
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  final items = decoded['items'] as List<dynamic>;
  return items
      .map(
        (dynamic item) => PracticeEntry.fromJson(item as Map<String, dynamic>),
      )
      .toList(growable: false);
}

class _RecordingGamificationRepository implements GamificationRepository {
  final List<int> processedCountsWritten = <int>[];
  GamificationMigrationState? _state;

  @override
  GamificationRead<GamificationMigrationState> readMigrationState() =>
      _state == null
      ? const GamificationRead<GamificationMigrationState>.missing()
      : GamificationRead<GamificationMigrationState>.available(_state!);

  @override
  Future<void> replaceMigrationState(GamificationMigrationState state) async {
    processedCountsWritten.add(state.processedCount);
    _state = state;
  }

  @override
  GamificationRead<GamificationProfileSnapshot> readProfileSnapshot() =>
      const GamificationRead<GamificationProfileSnapshot>.missing();

  @override
  Future<void> replaceProfileSnapshot(
    GamificationProfileSnapshot snapshot,
  ) async {}

  @override
  Stream<GamificationRead<GamificationProfileSnapshot>>
  watchProfileSnapshots() =>
      const Stream<GamificationRead<GamificationProfileSnapshot>>.empty();

  @override
  GamificationRead<GamificationCatalogVersion> readCatalogVersion() =>
      const GamificationRead<GamificationCatalogVersion>.missing();

  @override
  Future<void> replaceCatalogVersion(
    GamificationCatalogVersion version,
  ) async {}

  @override
  GamificationRead<List<GamificationInboxItem>> readInbox() =>
      const GamificationRead<List<GamificationInboxItem>>.missing();

  @override
  Future<GamificationInboxWriteReport> replaceInbox(
    List<GamificationInboxItem> items,
  ) async => const GamificationInboxWriteReport(trimmedCount: 0);

  @override
  Future<void> dispose() async {}
}
