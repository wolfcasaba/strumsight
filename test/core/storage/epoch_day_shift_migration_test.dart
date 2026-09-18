import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/logging/app_logger.dart';
import 'package:strumsight/core/storage/json_document_store.dart';
import 'package:strumsight/core/storage/key_value_store.dart';
import 'package:strumsight/core/storage/storage_keys.dart';
import 'package:strumsight/core/storage/storage_migrator.dart';

import 'in_memory_key_value_store.dart';

/// ADR 0583 — the persisted epoch days were written by a conversion that
/// anchored the calendar date at LOCAL midnight, so a device east of UTC stored
/// one day less than the true epoch day. This step repairs those values; the
/// conversion itself is repaired in `lib/core/foundation/epoch_day.dart`.
///
/// Every case in this file — including the ones that run the SHIPPED
/// `appStorageMigrations` list — pins the offset AND the clock explicitly, so
/// the numbers mean the same thing on the UTC+2 dev box and on a UTC CI runner.
/// At UTC the repair is a no-op by design, so a cell that let the runner decide
/// would assert nothing.
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

/// 2026-09-18 12:00 UTC. At +02:00 and at −05:00 alike the local calendar date
/// is still 2026-09-18, i.e. epoch day 20714 — so "today" is the same integer
/// in every case below and the assertions differ only in what they measure.
final _migrationClock = DateTime.utc(2026, 9, 18, 12);
const _today = 20714;

const _streakDoc = EpochDayDocument(
  key: StorageKeys.streak,
  shape: JsonBodyShape.object,
  bodyKey: 'data',
  fields: ['last'],
);

const _logDoc = EpochDayDocument(
  key: StorageKeys.practiceLog,
  shape: JsonBodyShape.list,
  fields: ['day'],
);

String _streakDocument(Map<String, Object?> data) =>
    jsonEncode({'schemaVersion': documentSchemaVersion, 'data': data});

String _practiceLog(List<Map<String, Object?>> items) =>
    jsonEncode({'schemaVersion': documentSchemaVersion, 'items': items});

Map<String, dynamic> _decode(String? raw) =>
    jsonDecode(raw!) as Map<String, dynamic>;

List<Object?> _items(InMemoryKeyValueStore store) =>
    _decode(store.readString(StorageKeys.practiceLog))['items']
        as List<Object?>;

Map<String, dynamic> _streakData(InMemoryKeyValueStore store) =>
    _decode(store.readString(StorageKeys.streak))['data']
        as Map<String, dynamic>;

void main() {
  late InMemoryKeyValueStore store;
  late _RecordingLogger logger;

  setUp(() {
    store = InMemoryKeyValueStore();
    logger = _RecordingLogger();
  });

  EpochDayShiftMigration shift(
    Duration offset,
    List<EpochDayDocument> documents,
  ) => EpochDayShiftMigration(
    version: 1,
    id: 'test.epoch_day_shift',
    documents: documents,
    deviceUtcOffset: () => offset,
    clock: () => _migrationClock,
  );

  EpochDayShiftMigration streakShift(Duration offset) =>
      shift(offset, const [_streakDoc]);

  EpochDayShiftMigration logShift(Duration offset) =>
      shift(offset, const [_logDoc]);

  /// The shape the app ships: both documents under ONE step, so one reading of
  /// the device offset decides both and they can never come apart.
  EpochDayShiftMigration bothShift(Duration offset) =>
      shift(offset, const [_streakDoc, _logDoc]);

  group('the device offset decides the shift', () {
    test("shifts the streak's last practice day by +1 east of UTC", () async {
      // Two days back, so the repaired day is still strictly before today and
      // the "never onto today" bound has nothing to say about it.
      store.values[StorageKeys.streak] = _streakDocument({
        'current': 7,
        'longest': 9,
        'last': 20712,
        'freezes': 1,
        'total': 30,
      });

      await streakShift(const Duration(hours: 2)).apply(store, logger);

      final data = _streakData(store);
      expect(data['last'], 20713);
      expect(data['current'], 7, reason: 'counters are not epoch days');
      expect(data['longest'], 9);
      expect(data['freezes'], 1);
      expect(data['total'], 30);
    });

    test('shifts every practice-log day total by +1', () async {
      store.values[StorageKeys.practiceLog] = _practiceLog([
        {'day': 20711, 'src': 'live', 'sec': 60},
        {'day': 20712, 'src': 'learn', 'sec': 120},
      ]);

      await logShift(
        const Duration(hours: 5, minutes: 30),
      ).apply(store, logger);

      final items = _items(store);
      expect(items.map((e) => (e as Map<String, dynamic>)['day']), [
        20712,
        20713,
      ]);
      expect(
        (items.first as Map<String, dynamic>)['sec'],
        60,
        reason: 'only the day field moves',
      );
    });

    test('leaves the "never practised" sentinel alone', () async {
      store.values[StorageKeys.streak] = _streakDocument({
        'current': 0,
        'longest': 0,
        'last': -1,
        'freezes': 0,
        'total': 0,
      });

      await streakShift(const Duration(hours: 2)).apply(store, logger);

      expect(store.writeLog, isEmpty);
      expect(_streakData(store)['last'], -1);
    });

    test('a negative offset writes nothing — including for the traveller '
        'whose days DO need repairing', () async {
      // The other wrong-hemisphere case (ADR 0583 "Known limitation" 1): the
      // days were written in Budapest, so 20713 really is one short, but the
      // update runs in New York. The device offset is the only input there is,
      // and it says "nothing to do" — the day stays short, once, and the
      // schema version still advances, so the repair never runs again. This
      // test pins that accepted cost so it cannot be mistaken for a bug later.
      final stored = _streakDocument({
        'current': 7,
        'longest': 9,
        'last': 20713,
        'freezes': 1,
        'total': 30,
      });
      store.values[StorageKeys.streak] = stored;

      await streakShift(const Duration(hours: -5)).apply(store, logger);

      expect(store.writeLog, isEmpty);
      expect(store.readString(StorageKeys.streak), stored);
    });

    test('a zero offset writes nothing', () async {
      store.values[StorageKeys.streak] = _streakDocument({
        'current': 1,
        'longest': 1,
        'last': 20713,
        'freezes': 0,
        'total': 1,
      });

      await streakShift(Duration.zero).apply(store, logger);

      expect(store.writeLog, isEmpty);
    });
  });

  group('a repaired day never reaches today, let alone passes it', () {
    test('the traveller whose stored day is already today keeps it', () async {
      // The wrong-hemisphere case the fallback cannot see: the days were
      // written west of UTC (so they are already right) and the device is east
      // of UTC when the update runs. The bound refuses the shift that would
      // make `lastPracticeDay` tomorrow — which is the damaging outcome,
      // because `StreakLogic.applyPractice` returns early while today is not
      // after the stored day, so the user's practice would stop being counted.
      store.values[StorageKeys.streak] = _streakDocument({
        'current': 3,
        'longest': 3,
        'last': _today,
        'freezes': 0,
        'total': 3,
      });

      await streakShift(const Duration(hours: 9)).apply(store, logger);

      expect(_streakData(store)['last'], _today);
      expect(store.writeLog, isEmpty);
      expect(
        logger.events,
        contains('warning:storage.migration.epoch_day_not_in_the_past'),
      );
    });

    test('the traveller who practised YESTERDAY west of UTC keeps yesterday: '
        'an over-shift may not land ON today either', () async {
      // Same wrong-hemisphere traveller as above, one day earlier: written west
      // of UTC (so 20713 is already the true day), practised YESTERDAY, updates
      // east of UTC. A `>` bound would allow 20713 -> 20714 because that is not
      // in the FUTURE — but `StreakLogic.applyPractice` short-circuits on
      // `today <= lastPracticeDay`, so landing exactly ON today costs the user
      // the same two things a future day does: a practice day they never had,
      // and their practice on the upgrade day silently not recorded. The price
      // of the strict bound is in ADR 0583 D4: an EASTERN user whose newest
      // stored day really was short keeps it short, once.
      final stored = _streakDocument({
        'current': 4,
        'longest': 6,
        'last': _today - 1,
        'freezes': 0,
        'total': 12,
      });
      store.values[StorageKeys.streak] = stored;

      await streakShift(const Duration(hours: 2)).apply(store, logger);

      expect(_streakData(store)['last'], _today - 1);
      expect(store.readString(StorageKeys.streak), stored);
      expect(store.writeLog, isEmpty);
      expect(
        logger.events,
        contains('warning:storage.migration.epoch_day_not_in_the_past'),
      );
    });

    test('older records in the same document are still repaired', () async {
      store.values[StorageKeys.practiceLog] = _practiceLog([
        {'day': 20711, 'src': 'live', 'sec': 60},
        {'day': _today, 'src': 'live', 'sec': 60},
      ]);

      await logShift(const Duration(hours: 2)).apply(store, logger);

      expect(
        _items(store).map((e) => (e as Map<String, dynamic>)['day']),
        [20712, _today],
        reason: 'the bound is per record, not per document',
      );
    });
  });

  group('non-destructive and loud', () {
    test('a document it cannot parse is kept, not destroyed', () async {
      store.values[StorageKeys.practiceLog] = 'not json at all';

      await logShift(const Duration(hours: 2)).apply(store, logger);

      expect(store.readString(StorageKeys.practiceLog), 'not json at all');
      expect(logger.events, contains('warning:storage.migration.unparsable'));
    });

    test('a document with an unexpected body shape is left alone', () async {
      final wrongShape = jsonEncode({
        'schemaVersion': documentSchemaVersion,
        'data': 'a string where the object should be',
      });
      store.values[StorageKeys.streak] = wrongShape;

      await streakShift(const Duration(hours: 2)).apply(store, logger);

      expect(store.readString(StorageKeys.streak), wrongShape);
      expect(
        logger.events,
        contains('warning:storage.migration.unexpected_shape'),
      );
    });

    test('a list record that is not an object is copied through', () async {
      store.values[StorageKeys.practiceLog] = _practiceLog([
        {'day': 20711, 'src': 'live', 'sec': 60},
      ]).replaceFirst('[{', '["junk",{');

      await logShift(const Duration(hours: 2)).apply(store, logger);

      expect(_items(store).first, 'junk');
      expect((_items(store)[1] as Map<String, dynamic>)['day'], 20712);
    });

    test('an absent document writes nothing', () async {
      await logShift(const Duration(hours: 2)).apply(store, logger);
      expect(store.writeLog, isEmpty);
    });

    test('both documents of one step move together under a single offset '
        'reading', () async {
      store.values[StorageKeys.streak] = _streakDocument({
        'current': 7,
        'longest': 9,
        'last': 20712,
        'freezes': 1,
        'total': 30,
      });
      store.values[StorageKeys.practiceLog] = _practiceLog([
        {'day': 20711, 'src': 'live', 'sec': 60},
      ]);

      await bothShift(const Duration(hours: 2)).apply(store, logger);

      expect(_streakData(store)['last'], 20713);
      expect((_items(store).single as Map<String, dynamic>)['day'], 20712);
    });

    test('a refused write on the second document rolls the first one back, so '
        'the retry cannot shift it twice', () async {
      // This is what the ONE-step shape costs and how it is paid: merging 23
      // and 24 removes the "retried after a hemisphere change" split (ADR 0583
      // D4), but it would open a partial-write window unless the step undoes
      // what it already wrote. It does, so the next boot re-enters the step on
      // an UNSHIFTED store.
      final streakBefore = _streakDocument({
        'current': 7,
        'longest': 9,
        'last': 20712,
        'freezes': 1,
        'total': 30,
      });
      final logBefore = _practiceLog([
        {'day': 20711, 'src': 'live', 'sec': 60},
      ]);
      store.values[StorageKeys.streak] = streakBefore;
      store.values[StorageKeys.practiceLog] = logBefore;
      store.failingKeys.add(StorageKeys.practiceLog);

      await expectLater(
        bothShift(const Duration(hours: 2)).apply(store, logger),
        throwsA(isA<StorageException>()),
        reason: 'the refusal is still loud: the migrator must stop',
      );

      expect(
        store.readString(StorageKeys.streak),
        streakBefore,
        reason: 'the document written before the refusal is put back verbatim',
      );
      expect(store.readString(StorageKeys.practiceLog), logBefore);
    });

    test('a refused write throws and leaves the document exactly as it '
        'was', () async {
      final stored = _practiceLog([
        {'day': 20711, 'src': 'live', 'sec': 60},
      ]);
      store.values[StorageKeys.practiceLog] = stored;
      store.failingKeys.add(StorageKeys.practiceLog);

      await expectLater(
        logShift(const Duration(hours: 2)).apply(store, logger),
        throwsA(isA<StorageException>()),
        reason:
            'a refused write is loud: the migrator stops and the schema '
            'version stays put, so this step runs again on the next boot',
      );

      expect(store.readString(StorageKeys.practiceLog), stored);
    });
  });

  group('the shipped migration list', () {
    /// The shipped list with its epoch-day repair pinned to a device at
    /// `+02:00` and to [_migrationClock].
    ///
    /// At UTC the repair is a no-op BY DESIGN, so a cell that ran the list at
    /// the runner's own offset would assert nothing at all on a UTC CI box.
    /// Only the identity of the steps is read off `appStorageMigrations`
    /// directly; everything that measures a shifted value runs through this.
    List<StorageMigration> eastOfUtc() => [
      for (final migration in appStorageMigrations)
        if (migration is EpochDayShiftMigration)
          EpochDayShiftMigration(
            version: migration.version,
            id: migration.id,
            documents: migration.documents,
            deviceUtcOffset: () => const Duration(hours: 2),
            clock: () => _migrationClock,
          )
        else
          migration,
    ];

    Future<StorageMigrationReport> migrate() => StorageMigrator(
      store: store,
      logger: logger,
      migrations: eastOfUtc(),
    ).migrate();

    test('carries the epoch-day repair as its single newest, forward-only '
        'step', () {
      final ids = appStorageMigrations.map((m) => m.id).toList();
      final versions = appStorageMigrations.map((m) => m.version).toList();

      expect(versions, versions.toList()..sort());
      expect(versions.toSet().length, versions.length);
      expect(
        ids.last,
        'r-c1.epoch_day_shift',
        reason: 'the repair must run after the renames that create the keys',
      );
      final repairs = appStorageMigrations
          .whereType<EpochDayShiftMigration>()
          .toList();
      expect(
        repairs,
        hasLength(1),
        reason:
            'ONE step, not one per document: both documents have to move '
            'under the same reading of the device offset, or a write failure '
            'retried after a hemisphere change leaves them a day apart',
      );
      expect(
        repairs.single.documents.map((d) => d.key),
        [StorageKeys.streak, StorageKeys.practiceLog],
        reason: 'the step repairs both epoch-day documents ADR 0583 surveyed',
      );
    });

    test('runs end to end through the migrator and bumps the schema '
        'version', () async {
      store.values[StorageKeys.schemaVersion] =
          appStorageMigrations.last.version - 1;

      final report = await migrate();

      expect(report.isComplete, isTrue);
      expect(report.applied, ['r-c1.epoch_day_shift']);
      expect(
        store.readInt(StorageKeys.schemaVersion),
        appStorageMigrations.last.version,
      );
    });

    test('the schema-version gate is the whole idempotence: a save between '
        'two runs is not shifted twice', () async {
      // The window the earlier design tried to cover with a breadcrumb inside
      // the envelope — which `JsonDocumentStore.write` erases on the next save.
      // The version gate covers it by itself: the step completed, so its
      // version is recorded and it is never entered again, whatever the user
      // saves afterwards. Pinned to +02:00 so the first run really does shift
      // the day — at UTC this cell would pass without anything happening.
      store.values[StorageKeys.schemaVersion] =
          appStorageMigrations.last.version - 1;
      store.values[StorageKeys.streak] = _streakDocument({
        'current': 7,
        'longest': 9,
        'last': 20712,
        'freezes': 1,
        'total': 30,
      });

      final first = await migrate();
      final afterMigration = _streakData(store)['last'];
      expect(
        afterMigration,
        20713,
        reason: 'the first run must actually have shifted the day',
      );

      await JsonDocumentStore(
        store: store,
        logger: logger,
        key: StorageKeys.streak,
        legacyKey: LegacyStorageKeys.streak,
        name: 'streak',
        bodyKey: 'data',
      ).write({
        'current': 7,
        'longest': 9,
        'last': afterMigration,
        'freezes': 1,
        'total': 30,
      });

      final second = await migrate();

      expect(first.applied, isNotEmpty);
      expect(second.applied, isEmpty, reason: 'nothing is pending any more');
      expect(
        _streakData(store)['last'],
        afterMigration,
        reason: 'the stored day is repaired exactly once, ever',
      );
    });
  });
}
