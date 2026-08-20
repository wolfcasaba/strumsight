import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/logging/app_logger.dart';
import 'package:strumsight/core/storage/json_document_store.dart';
import 'package:strumsight/core/storage/key_value_store.dart';
import 'package:strumsight/features/gamification/data/gamification_repository.dart';
import 'package:strumsight/features/gamification/data/gamification_storage_schema.dart';
import 'package:strumsight/features/gamification/data/local_gamification_repository.dart';

import '../../../support/preference_store.dart';

void main() {
  group('Gamification repository — versioned documents', () {
    test(
      'A1: an interrupted profile replacement keeps the previous complete snapshot',
      () async {
        final store = _InterruptingStore();
        final repository = _repository(store);
        const previous = GamificationProfileSnapshot(totalXp: 125);

        await repository.replaceProfileSnapshot(previous);
        store.interruptNextProfileWrite = true;
        await repository.replaceProfileSnapshot(
          const GamificationProfileSnapshot(totalXp: 250),
        );

        expect(
          store.writeLog,
          isNot(contains('remove:${GamificationStorageKeys.profileSnapshot}')),
        );
        expect(_profileSnapshot(_repository(store)).totalXp, previous.totalXp);
      },
    );

    test(
      'A2: a corrupt profile snapshot is reported and read leaves its bytes intact',
      () {
        const corruptBytes = '{this is not json';
        final store = InMemoryKeyValueStore(<String, Object>{
          GamificationStorageKeys.profileSnapshot: corruptBytes,
        });

        final read = _repository(store).readProfileSnapshot();

        expect(read.status, GamificationReadStatus.corrupt);
        expect(
          store.readString(GamificationStorageKeys.profileSnapshot),
          corruptBytes,
        );
      },
    );

    test(
      'A2: saving after corruption preserves the unreadable bytes in quarantine',
      () async {
        const corruptBytes = '{this is not json';
        final store = InMemoryKeyValueStore(<String, Object>{
          GamificationStorageKeys.profileSnapshot: corruptBytes,
        });
        final repository = _repository(store);

        expect(
          repository.readProfileSnapshot().status,
          GamificationReadStatus.corrupt,
        );
        await repository.replaceProfileSnapshot(
          const GamificationProfileSnapshot(totalXp: 15),
        );

        expect(
          store.readString(
            '${GamificationStorageKeys.profileSnapshot}.corrupt',
          ),
          corruptBytes,
        );
        expect(_profileSnapshot(_repository(store)).totalXp, 15);
      },
    );

    test('A2: a malformed inbox record does not hide valid records', () {
      final store = InMemoryKeyValueStore(<String, Object>{
        GamificationStorageKeys.rewardInbox: jsonEncode(<String, Object?>{
          'schemaVersion': documentSchemaVersion,
          'items': <Object?>[
            _inboxItem('inbox-good-1').toJson(),
            <String, Object?>{
              'schemaVersion': gamificationStorageSchemaVersion,
              'createdAt': '2026-08-20T12:01:00.000Z',
            },
            _inboxItem('inbox-good-2').toJson(),
          ],
        }),
      });

      final read = _repository(store).readInbox();

      expect(read.status, GamificationReadStatus.available);
      expect(read.value, hasLength(2));
      expect(read.value!.map((item) => item.id), <String>[
        'inbox-good-1',
        'inbox-good-2',
      ]);
    });

    test('concurrent profile replacements persist their call order', () async {
      final store = _InterruptingStore()..holdNextProfileWrite = true;
      final repository = _repository(store);

      final first = repository.replaceProfileSnapshot(
        const GamificationProfileSnapshot(totalXp: 20),
      );
      await store.profileWriteStarted.future;
      final second = repository.replaceProfileSnapshot(
        const GamificationProfileSnapshot(totalXp: 40),
      );
      store.releaseHeldProfileWrite();
      await Future.wait<void>(<Future<void>>[first, second]);

      expect(_profileSnapshot(_repository(store)).totalXp, 40);
    });

    test(
      'A3: every persisted gamification DTO rejects a future schema version',
      () {
        final futureVersion = gamificationStorageSchemaVersion + 1;

        expect(
          () => GamificationProfileSnapshot.fromJson(<String, dynamic>{
            'schemaVersion': futureVersion,
            'totalXp': 1,
          }),
          throwsFormatException,
        );
        expect(
          () => GamificationCatalogVersion.fromJson(<String, dynamic>{
            'schemaVersion': futureVersion,
            'catalogVersion': 1,
          }),
          throwsFormatException,
        );
        expect(
          () => GamificationInboxItem.fromJson(<String, dynamic>{
            'schemaVersion': futureVersion,
            'id': 'inbox-1',
            'createdAt': '2026-08-20T00:00:00.000Z',
          }),
          throwsFormatException,
        );
        expect(
          () => GamificationMigrationState.fromJson(<String, dynamic>{
            'schemaVersion': futureVersion,
          }),
          throwsFormatException,
        );
      },
    );

    test(
      'A3: all four documents round-trip their current model version',
      () async {
        final store = InMemoryKeyValueStore();
        final repository = _repository(store);
        const profile = GamificationProfileSnapshot(totalXp: 99);
        const catalog = GamificationCatalogVersion(catalogVersion: 4);
        const migration = GamificationMigrationState();
        final inboxItem = _inboxItem('inbox-1');

        await repository.replaceProfileSnapshot(profile);
        await repository.replaceCatalogVersion(catalog);
        await repository.replaceInbox(<GamificationInboxItem>[inboxItem]);
        await repository.replaceMigrationState(migration);

        final reloaded = _repository(store);
        expect(
          _profileSnapshot(reloaded).schemaVersion,
          gamificationStorageSchemaVersion,
        );
        expect(
          _catalogVersion(reloaded).schemaVersion,
          gamificationStorageSchemaVersion,
        );
        expect(
          _inbox(reloaded).value!.single.schemaVersion,
          gamificationStorageSchemaVersion,
        );
        expect(
          _migrationState(reloaded).value!.schemaVersion,
          gamificationStorageSchemaVersion,
        );
      },
    );
  });

  group('Gamification repository — repository boundary', () {
    test('A4: a pure Dart fake can implement the storage-free contract', () {
      final fake = _FakeGamificationRepository(
        const GamificationProfileSnapshot(totalXp: 30),
      );
      final source = File(
        'lib/features/gamification/data/gamification_repository.dart',
      ).readAsStringSync();

      expect(fake.readProfileSnapshot().value!.totalXp, 30);
      expect(source, isNot(contains('JsonDocumentStore')));
      expect(source, isNot(contains('KeyValueStore')));
    });

    test(
      'A6: a profile watcher publishes the fresh value after replacement',
      () async {
        final repository = _repository(InMemoryKeyValueStore());
        final next = repository.watchProfileSnapshots().first;

        await repository.replaceProfileSnapshot(
          const GamificationProfileSnapshot(totalXp: 80),
        );

        expect((await next).value!.totalXp, 80);
        await repository.dispose();
      },
    );
  });

  group('Gamification repository — bounded reward inbox', () {
    test(
      'A7: the inbox limit is inclusive and only trims the oldest over capacity',
      () async {
        final repository = _repository(InMemoryKeyValueStore());
        final belowLimit = _inboxItems(inboxRetentionLimit - 1);
        final atLimit = _inboxItems(inboxRetentionLimit);
        final aboveLimit = _inboxItems(inboxRetentionLimit + 1);

        final belowReport = await repository.replaceInbox(belowLimit);
        expect(belowReport.trimmedCount, 0);
        expect(_inbox(repository).value, hasLength(inboxRetentionLimit - 1));

        final atReport = await repository.replaceInbox(atLimit);
        expect(atReport.trimmedCount, 0);
        expect(_inbox(repository).value, hasLength(inboxRetentionLimit));

        final aboveReport = await repository.replaceInbox(aboveLimit);
        final retained = _inbox(repository).value!;
        expect(aboveReport.trimmedCount, 1);
        expect(retained, hasLength(inboxRetentionLimit));
        expect(retained.first.id, 'inbox-1');
        expect(retained.last.id, 'inbox-$inboxRetentionLimit');
      },
    );

    test(
      'A8: all four gamification storage keys are unique and centralized in the schema',
      () {
        expect(GamificationStorageKeys.all, hasLength(4));
        expect(GamificationStorageKeys.all.toSet(), hasLength(4));
        expect(
          GamificationStorageKeys.all,
          containsAll(<String>[
            GamificationStorageKeys.profileSnapshot,
            GamificationStorageKeys.catalogVersion,
            GamificationStorageKeys.rewardInbox,
            GamificationStorageKeys.migrationState,
          ]),
        );
      },
    );
  });
}

LocalGamificationRepository _repository(KeyValueStore store) =>
    LocalGamificationRepository(store: store, logger: const NoopAppLogger());

GamificationProfileSnapshot _profileSnapshot(
  GamificationRepository repository,
) {
  final read = repository.readProfileSnapshot();
  expect(read.status, GamificationReadStatus.available);
  return read.value!;
}

GamificationCatalogVersion _catalogVersion(GamificationRepository repository) {
  final read = repository.readCatalogVersion();
  expect(read.status, GamificationReadStatus.available);
  return read.value!;
}

GamificationRead<List<GamificationInboxItem>> _inbox(
  GamificationRepository repository,
) {
  final read = repository.readInbox();
  expect(read.status, GamificationReadStatus.available);
  return read;
}

GamificationRead<GamificationMigrationState> _migrationState(
  GamificationRepository repository,
) {
  final read = repository.readMigrationState();
  expect(read.status, GamificationReadStatus.available);
  return read;
}

GamificationInboxItem _inboxItem(String id) =>
    GamificationInboxItem(id: id, createdAt: DateTime.utc(2026, 8, 20, 12));

List<GamificationInboxItem> _inboxItems(int count) => <GamificationInboxItem>[
  for (var index = 0; index < count; index++)
    GamificationInboxItem(
      id: 'inbox-$index',
      createdAt: DateTime.utc(2026, 8, 20, 12, index),
    ),
];

final class _FakeGamificationRepository implements GamificationRepository {
  _FakeGamificationRepository(GamificationProfileSnapshot profile)
    : _profile = GamificationRead<GamificationProfileSnapshot>.available(
        profile,
      );

  GamificationRead<GamificationProfileSnapshot> _profile;

  @override
  GamificationRead<GamificationCatalogVersion> readCatalogVersion() =>
      const GamificationRead<GamificationCatalogVersion>.missing();

  @override
  GamificationRead<List<GamificationInboxItem>> readInbox() =>
      const GamificationRead<List<GamificationInboxItem>>.available(
        <GamificationInboxItem>[],
      );

  @override
  GamificationRead<GamificationMigrationState> readMigrationState() =>
      const GamificationRead<GamificationMigrationState>.missing();

  @override
  GamificationRead<GamificationProfileSnapshot> readProfileSnapshot() =>
      _profile;

  @override
  Future<void> replaceCatalogVersion(GamificationCatalogVersion value) async {}

  @override
  Future<GamificationInboxWriteReport> replaceInbox(
    List<GamificationInboxItem> values,
  ) async => const GamificationInboxWriteReport(trimmedCount: 0);

  @override
  Future<void> replaceMigrationState(GamificationMigrationState value) async {}

  @override
  Future<void> replaceProfileSnapshot(GamificationProfileSnapshot value) async {
    _profile = GamificationRead<GamificationProfileSnapshot>.available(value);
  }

  @override
  Future<void> dispose() async {}

  @override
  Stream<GamificationRead<GamificationProfileSnapshot>>
  watchProfileSnapshots() =>
      const Stream<GamificationRead<GamificationProfileSnapshot>>.empty();
}

final class _InterruptingStore implements KeyValueStore {
  final InMemoryKeyValueStore _delegate = InMemoryKeyValueStore();

  bool interruptNextProfileWrite = false;
  bool holdNextProfileWrite = false;
  final Completer<void> profileWriteStarted = Completer<void>();
  final Completer<void> _releaseHeldProfileWrite = Completer<void>();

  List<String> get writeLog => _delegate.writeLog;

  void releaseHeldProfileWrite() => _releaseHeldProfileWrite.complete();

  @override
  bool contains(String key) => _delegate.contains(key);

  @override
  String? readString(String key) => _delegate.readString(key);

  @override
  int? readInt(String key) => _delegate.readInt(key);

  @override
  double? readDouble(String key) => _delegate.readDouble(key);

  @override
  bool? readBool(String key) => _delegate.readBool(key);

  @override
  List<String>? readStringList(String key) => _delegate.readStringList(key);

  @override
  Future<void> remove(String key) => _delegate.remove(key);

  @override
  Future<void> writeString(String key, String value) {
    if (key == GamificationStorageKeys.profileSnapshot &&
        interruptNextProfileWrite) {
      interruptNextProfileWrite = false;
      return Future<void>.error(
        StorageException(FailureCode.storageWrite, key: key),
      );
    }
    if (key == GamificationStorageKeys.profileSnapshot &&
        holdNextProfileWrite) {
      holdNextProfileWrite = false;
      profileWriteStarted.complete();
      return _releaseHeldProfileWrite.future.then<void>(
        (_) => _delegate.writeString(key, value),
      );
    }
    return _delegate.writeString(key, value);
  }

  @override
  Future<void> writeInt(String key, int value) =>
      _delegate.writeInt(key, value);

  @override
  Future<void> writeDouble(String key, double value) =>
      _delegate.writeDouble(key, value);

  @override
  Future<void> writeBool(String key, bool value) =>
      _delegate.writeBool(key, value);

  @override
  Future<void> writeStringList(String key, List<String> value) =>
      _delegate.writeStringList(key, value);
}
