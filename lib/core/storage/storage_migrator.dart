import 'dart:convert';

import '../foundation/app_failure.dart';
import '../foundation/epoch_day.dart';
import '../logging/app_logger.dart';
import 'json_document_store.dart';
import 'key_value_store.dart';
import 'storage_keys.dart';

/// One forward-only step of the persisted-storage schema (SDD Ch2 Kör 5 §5.3).
///
/// Contract every implementation must honour:
///
/// * **idempotent** — running it twice does the same as running it once;
/// * **resumable** — it may be interrupted (process death) at any await and
///   must complete correctly on the next boot;
/// * **non-destructive** — old data is removed only after the new write has
///   been confirmed;
/// * **loud** — an operation it cannot complete throws, so the migrator can
///   stop and keep the data instead of advancing past it.
abstract interface class StorageMigration {
  /// 1-based, matches this migration's position in the app's migration list.
  int get version;

  /// Stable identifier used in logs; never reused.
  String get id;

  Future<void> apply(KeyValueStore store, AppLogger logger);
}

/// Moves a value from a pre-namespace key to its `ss.` key.
///
/// The bread-and-butter migration for Kör 6–7: every migrated feature gets one
/// of these instead of hand-written copy code, so the interrupted-migration and
/// corrupt-value behaviour is written (and tested) exactly once.
class RenameKeyMigration implements StorageMigration {
  const RenameKeyMigration.string({
    required this.version,
    required this.id,
    required this.from,
    required this.to,
  }) : _kind = _ValueKind.string;

  const RenameKeyMigration.boolean({
    required this.version,
    required this.id,
    required this.from,
    required this.to,
  }) : _kind = _ValueKind.boolean;

  const RenameKeyMigration.integer({
    required this.version,
    required this.id,
    required this.from,
    required this.to,
  }) : _kind = _ValueKind.integer;

  const RenameKeyMigration.number({
    required this.version,
    required this.id,
    required this.from,
    required this.to,
  }) : _kind = _ValueKind.number;

  const RenameKeyMigration.stringList({
    required this.version,
    required this.id,
    required this.from,
    required this.to,
  }) : _kind = _ValueKind.stringList;

  @override
  final int version;

  @override
  final String id;

  final String from;
  final String to;
  final _ValueKind _kind;

  @override
  Future<void> apply(KeyValueStore store, AppLogger logger) async {
    if (store.contains(to)) {
      // Either already migrated, or the process died between the write and the
      // removal. Never overwrite the new value with the stale one.
      if (store.contains(from)) await store.remove(from);
      return;
    }
    if (!store.contains(from)) return;

    final value = _readFrom(store);
    if (value == null) {
      // Present but unreadable as this type (corrupt or written by an older
      // build with a different type). Leave it on disk — the feature falls back
      // to its default, and nothing is destroyed.
      logger.warning(
        'storage.migration.unreadable_value',
        fields: {'migration': id, 'key': from},
      );
      return;
    }

    await _writeTo(store, value);
    await store.remove(from);
  }

  Object? _readFrom(KeyValueStore store) => switch (_kind) {
    _ValueKind.string => store.readString(from),
    _ValueKind.boolean => store.readBool(from),
    _ValueKind.integer => store.readInt(from),
    _ValueKind.number => store.readDouble(from),
    _ValueKind.stringList => store.readStringList(from),
  };

  Future<void> _writeTo(KeyValueStore store, Object value) => switch (_kind) {
    _ValueKind.string => store.writeString(to, value as String),
    _ValueKind.boolean => store.writeBool(to, value as bool),
    _ValueKind.integer => store.writeInt(to, value as int),
    _ValueKind.number => store.writeDouble(to, value as double),
    _ValueKind.stringList => store.writeStringList(to, value as List<String>),
  };
}

enum _ValueKind { string, boolean, integer, number, stringList }

/// The shape a legacy JSON blob is expected to have.
enum JsonBodyShape { list, object }

/// Moves a pre-envelope JSON blob to its `ss.` key **and** wraps it in the
/// versioned document envelope (Kör 7 §7.3).
///
/// The workhorse migration for the six user-content documents. It keeps
/// [RenameKeyMigration]'s contract — write before remove, never overwrite an
/// already-migrated document, never destroy an unreadable value — and adds one
/// rule: a blob it cannot parse is **left on the legacy key**. The owning
/// repository still reads legacy keys, so an unparseable blob reaches the
/// document store, which quarantines it on the next write instead of the
/// migrator deleting it here.
class WrapJsonDocumentMigration implements StorageMigration {
  const WrapJsonDocumentMigration({
    required this.version,
    required this.id,
    required this.from,
    required this.to,
    required this.shape,
    this.bodyKey = 'items',
  });

  @override
  final int version;

  @override
  final String id;

  final String from;
  final String to;
  final JsonBodyShape shape;
  final String bodyKey;

  @override
  Future<void> apply(KeyValueStore store, AppLogger logger) async {
    if (store.contains(to)) {
      if (store.contains(from)) await store.remove(from);
      return;
    }
    if (!store.contains(from)) return;

    final raw = store.readString(from);
    if (raw == null || raw.isEmpty) {
      logger.warning(
        'storage.migration.unreadable_value',
        fields: {'migration': id, 'key': from},
      );
      return;
    }

    Object? body;
    try {
      body = jsonDecode(raw);
    } catch (e) {
      logger.warning(
        'storage.migration.unparsable_document',
        error: e,
        fields: {'migration': id, 'key': from},
      );
      return;
    }
    final matchesShape = switch (shape) {
      JsonBodyShape.list => body is List,
      JsonBodyShape.object => body is Map,
    };
    if (!matchesShape) {
      logger.warning(
        'storage.migration.unexpected_shape',
        fields: {'migration': id, 'key': from},
      );
      return;
    }

    await store.writeString(
      to,
      jsonEncode({'schemaVersion': documentSchemaVersion, bodyKey: body}),
    );
    await store.remove(from);
  }
}

/// One persisted document that holds epoch days, and where they sit in it.
///
/// Only the documents named in an [EpochDayShiftMigration] are rewritten by it;
/// ADR 0583 lists the epoch-day fields that were deliberately left alone and
/// why.
class EpochDayDocument {
  const EpochDayDocument({
    required this.key,
    required this.shape,
    required this.fields,
    this.bodyKey = 'items',
  });

  /// The namespaced key the document lives under.
  final String key;

  /// Whether the envelope body is the record list or a single object.
  final JsonBodyShape shape;

  /// Envelope field holding the payload — `items` for a collection, `data` for
  /// a single object (matches [JsonDocumentStore]).
  final String bodyKey;

  /// JSON keys of the epoch-day fields, inside the object or inside each list
  /// record.
  final List<String> fields;
}

/// Repairs epoch days written by the pre-[EpochDay] conversion (ADR 0583).
///
/// The old conversion anchored a calendar date at **local** midnight and then
/// truncated, so it answered `trueDay - 1` **at the offset the device had at
/// write time** when that offset was east of UTC, and `trueDay` at or west of
/// it. No stored byte records which of the two happened, and ADR 0583's survey
/// found that **neither** document repaired here carries a co-stored timestamp
/// that could say (`StreakData` persists `current`/`longest`/`last`/`freezes`/
/// `total`; `PracticeEntry` persists `day`/`src`/`sec`/`str`/`chd`/`dir`). So
/// the step is best effort, and the two rules it does have are the decision:
///
/// 1. **The device's current offset is the shift.** `+1` east of UTC, nothing
///    at or west of it. It is a guess about the past, and ADR 0583
///    §"Known limitation" names the users it is wrong for and what it costs
///    them. A per-record repair from a co-stored write timestamp would need no
///    guess — ADR 0583 D4 writes down the rule for the day a persisted day
///    carries one, and deliberately does not ship it against no caller.
/// 2. **Never onto today, and never past it.** A `+1` that would put a stored
///    day on or after "today" is refused **for that record**. Past today is a
///    day that has not happened; *on* today is just as damaging, because
///    `StreakLogic.applyPractice` returns early while `today <= lastPracticeDay`
///    — the user would be shown a practice day they never had, and their
///    practice on the upgrade day would go unrecorded. The price of the strict
///    bound (an eastern user whose newest stored day really was short keeps it
///    short, once) is written down in ADR 0583 D4.
///
/// **One step, every document, one reading of the offset.** Every document here
/// is repaired under a single `deviceUtcOffset()` call, so they can never end up
/// a day apart from one another — two steps could be interrupted between them
/// and resumed on a later boot after the device had crossed UTC. The documents
/// are repaired in memory first and written afterwards; a refused write rolls
/// the already-written ones back to their exact previous bytes before the
/// exception leaves here, so the migrator stops with the schema version
/// unchanged and the retry starts from an unshifted store. That is what keeps
/// the migrator's version gate the *whole* idempotence: a step that completed is
/// never entered again, and a step that threw shifted nothing. The step keeps no
/// marker of its own — an earlier design put one in the document envelope, where
/// `JsonDocumentStore.write` erases it on the user's very next save.
///
/// It keeps the migrator's other contracts:
///
/// * **non-destructive** — the one write per document replaces it with a value
///   derived from its own bytes, and only when something actually changed; a
///   document that cannot be parsed, or whose body has an unexpected shape, is
///   logged and **left exactly as it is** (same rule as
///   [WrapJsonDocumentMigration]) and costs the other documents nothing;
/// * **loud** — a store that refuses the write throws [StorageException] out of
///   here, so the migrator stops and the schema version does not advance.
class EpochDayShiftMigration implements StorageMigration {
  const EpochDayShiftMigration({
    required this.version,
    required this.id,
    required this.documents,
    this.deviceUtcOffset = _deviceUtcOffsetNow,
    this.clock = DateTime.now,
  });

  static Duration _deviceUtcOffsetNow() => DateTime.now().timeZoneOffset;

  @override
  final int version;

  @override
  final String id;

  /// The documents this step repairs, in write order. They share one reading of
  /// [deviceUtcOffset], and they are written all or none.
  final List<EpochDayDocument> documents;

  /// The device's current UTC offset — the fallback's only input. Injectable
  /// so a test pins the east-of-UTC and west-of-UTC behaviour explicitly
  /// instead of measuring the machine it happens to run on.
  final Duration Function() deviceUtcOffset;

  /// The migration clock. With [deviceUtcOffset] it gives "today", the day no
  /// repaired value may reach.
  final DateTime Function() clock;

  @override
  Future<void> apply(KeyValueStore store, AppLogger logger) async {
    final offset = deviceUtcOffset();
    // East of UTC the old expression lost a day; at or west of it it did not,
    // so there is nothing to repair — and nothing to read, either.
    if (offset <= Duration.zero) return;
    final today = EpochDay.ofInstant(clock(), offset);

    // Decide every document before writing any of them, so the loop below is
    // the only failure window and it is as short as it can be made.
    final pending = <_PendingShift>[];
    for (final document in documents) {
      final before = store.readString(document.key);
      if (before == null || before.isEmpty) continue;
      final after = _repaired(before, document, today, logger);
      if (after == null) continue;
      pending.add(_PendingShift(document.key, before, after));
    }

    final written = <_PendingShift>[];
    for (final shift in pending) {
      try {
        await store.writeString(shift.key, shift.after);
      } catch (_) {
        await _rollBack(store, logger, written);
        rethrow;
      }
      written.add(shift);
    }
    if (written.isEmpty) return;

    logger.info(
      'storage.migration.epoch_day_shifted',
      fields: {
        'migration': id,
        'keys': [for (final shift in written) shift.key],
        'offsetMinutes': offset.inMinutes,
      },
    );
  }

  /// The repaired bytes of [document], or `null` when there is nothing to
  /// write: unparsable, an unexpected body shape, or no field that moved.
  String? _repaired(
    String raw,
    EpochDayDocument document,
    int today,
    AppLogger logger,
  ) {
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (e) {
      logger.warning(
        'storage.migration.unparsable',
        error: e,
        fields: {'migration': id, 'key': document.key},
      );
      return null;
    }
    if (decoded is! Map<String, dynamic>) {
      logger.warning(
        'storage.migration.unexpected_shape',
        fields: {'migration': id, 'key': document.key},
      );
      return null;
    }

    var changed = false;

    Map<String, Object?> repair(Map<String, dynamic> record) {
      final out = Map<String, Object?>.of(record);
      for (final field in document.fields) {
        final stored = record[field];
        // A negative value is a sentinel ("never practised"), not a day.
        if (stored is! int || stored < 0) continue;
        if (stored + 1 >= today) {
          logger.warning(
            'storage.migration.epoch_day_not_in_the_past',
            fields: {
              'migration': id,
              'key': document.key,
              'field': field,
              'stored': stored,
              'today': today,
            },
          );
          continue;
        }
        out[field] = stored + 1;
        changed = true;
      }
      return out;
    }

    final body = decoded[document.bodyKey];
    final Object? repaired = switch (document.shape) {
      JsonBodyShape.object =>
        body is Map<String, dynamic> ? repair(body) : null,
      JsonBodyShape.list =>
        body is List
            ? [
                for (final record in body)
                  // A record that is not an object is already unreadable to its
                  // decoder, which skips it and keeps the rest of the history;
                  // copy it untouched rather than dropping it here.
                  if (record is Map<String, dynamic>)
                    repair(record)
                  else
                    record,
              ]
            : null,
    };
    if (repaired == null) {
      logger.warning(
        'storage.migration.unexpected_shape',
        fields: {'migration': id, 'key': document.key},
      );
      return null;
    }
    if (!changed) return null;

    return jsonEncode({...decoded, document.bodyKey: repaired});
  }

  /// Puts back the exact bytes of the documents this run already rewrote, so a
  /// refused write leaves the store as if the step had never started and the
  /// retry cannot shift a document a second time. Best effort: a restore that
  /// is refused too is logged, and the original failure is still what reaches
  /// the migrator.
  Future<void> _rollBack(
    KeyValueStore store,
    AppLogger logger,
    List<_PendingShift> written,
  ) async {
    for (final shift in written.reversed) {
      try {
        await store.writeString(shift.key, shift.before);
      } catch (e, stackTrace) {
        logger.error(
          'storage.migration.epoch_day_rollback_failed',
          error: e,
          stackTrace: stackTrace,
          fields: {'migration': id, 'key': shift.key},
        );
      }
    }
  }
}

/// One document's repaired bytes, held until every document has been decided.
class _PendingShift {
  const _PendingShift(this.key, this.before, this.after);

  final String key;
  final String before;
  final String after;
}

/// What a [StorageMigrator.migrate] run did — the caller logs it, tests assert
/// on it.
class StorageMigrationReport {
  const StorageMigrationReport({
    required this.fromVersion,
    required this.toVersion,
    required this.applied,
    this.failure,
  });

  /// Schema version found in the store.
  final int fromVersion;

  /// Schema version persisted after the run. Equals [fromVersion] when a
  /// migration failed — the failed step is retried on the next boot.
  final int toVersion;

  /// Ids of the migrations that completed, in order.
  final List<String> applied;

  /// Set when a migration threw; the remaining migrations were not attempted.
  final AppFailure? failure;

  bool get isComplete => failure == null;
}

/// Runs the pending [StorageMigration]s once per boot, before anything reads.
///
/// The version is written **after each** successful migration, so a run that
/// dies half-way resumes at the next pending step instead of replaying (or
/// skipping) completed ones. A migration that throws stops the run: the version
/// stays put, the data stays put, and the app boots normally on the values it
/// already has — a broken migration must never be a broken app.
class StorageMigrator {
  const StorageMigrator({
    required this.store,
    required this.logger,
    this.migrations = appStorageMigrations,
  });

  final KeyValueStore store;
  final AppLogger logger;
  final List<StorageMigration> migrations;

  Future<StorageMigrationReport> migrate() async {
    final from = store.readInt(StorageKeys.schemaVersion) ?? 0;
    final pending = migrations.where((m) => m.version > from).toList()
      ..sort((a, b) => a.version.compareTo(b.version));

    var current = from;
    final applied = <String>[];

    for (final migration in pending) {
      try {
        await migration.apply(store, logger);
        await store.writeInt(StorageKeys.schemaVersion, migration.version);
        current = migration.version;
        applied.add(migration.id);
      } catch (e, stackTrace) {
        logger.error(
          'storage.migration.failed',
          error: e,
          stackTrace: stackTrace,
          fields: {'migration': migration.id, 'version': migration.version},
        );
        return StorageMigrationReport(
          fromVersion: from,
          toVersion: current,
          applied: applied,
          failure: StorageFailure(
            code: FailureCode.storageWrite,
            cause: e,
            stackTrace: stackTrace,
          ),
        );
      }
    }

    if (applied.isNotEmpty) {
      logger.info(
        'storage.migration.completed',
        fields: {'from': from, 'to': current, 'applied': applied.length},
      );
    }
    return StorageMigrationReport(
      fromVersion: from,
      toVersion: current,
      applied: applied,
    );
  }
}

/// The app's migration list, in version order.
///
/// Schema **1–16** (E01-R06) move the simple preferences onto their namespaced
/// [StorageKeys] entries; **17–22** (E01-R07) move the six user-content
/// documents and wrap them in the versioned envelope. Each key is renamed in
/// the same round that moves its owner onto [KeyValueStore] — renaming while
/// the owner still reads the old key would lose the user's data. **23**
/// (ADR 0583) is the first step that repairs a *value* rather than a key: the
/// epoch days stored by the old local-midnight conversion.
///
/// One version per key for the renames, rather than one bulk step: a run
/// interrupted after the eighth rename resumes at the ninth instead of
/// replaying eight no-ops. The value repair is the one step that covers two
/// keys, because both of its documents must move under the *same* reading of
/// the device's UTC offset — see [EpochDayShiftMigration].
const List<StorageMigration> appStorageMigrations = [
  RenameKeyMigration.string(
    version: 1,
    id: 'r06.theme_mode',
    from: LegacyStorageKeys.themeMode,
    to: StorageKeys.themeMode,
  ),
  RenameKeyMigration.string(
    version: 2,
    id: 'r06.locale',
    from: LegacyStorageKeys.locale,
    to: StorageKeys.locale,
  ),
  RenameKeyMigration.number(
    version: 3,
    id: 'r06.confidence_threshold',
    from: LegacyStorageKeys.confidenceThreshold,
    to: StorageKeys.confidenceThreshold,
  ),
  RenameKeyMigration.integer(
    version: 4,
    id: 'r06.capo_fret',
    from: LegacyStorageKeys.capoFret,
    to: StorageKeys.capoFret,
  ),
  RenameKeyMigration.integer(
    version: 5,
    id: 'r06.tuning_a4',
    from: LegacyStorageKeys.tuningA4,
    to: StorageKeys.tuningA4,
  ),
  RenameKeyMigration.boolean(
    version: 6,
    id: 'r06.left_handed',
    from: LegacyStorageKeys.leftHanded,
    to: StorageKeys.leftHanded,
  ),
  RenameKeyMigration.integer(
    version: 7,
    id: 'r06.input_latency_ms',
    from: LegacyStorageKeys.inputLatencyMs,
    to: StorageKeys.inputLatencyMs,
  ),
  RenameKeyMigration.integer(
    version: 8,
    id: 'r06.visual_latency_ms',
    from: LegacyStorageKeys.visualLatencyMs,
    to: StorageKeys.visualLatencyMs,
  ),
  RenameKeyMigration.boolean(
    version: 9,
    id: 'r06.lab_mode',
    from: LegacyStorageKeys.labMode,
    to: StorageKeys.labMode,
  ),
  RenameKeyMigration.boolean(
    version: 10,
    id: 'r06.nudge_enabled',
    from: LegacyStorageKeys.nudgeEnabled,
    to: StorageKeys.nudgeEnabled,
  ),
  RenameKeyMigration.boolean(
    version: 11,
    id: 'r06.onboarding_seen',
    from: LegacyStorageKeys.onboardingSeen,
    to: StorageKeys.onboardingSeen,
  ),
  RenameKeyMigration.string(
    version: 12,
    id: 'r06.tuner_tuning',
    from: LegacyStorageKeys.tunerTuning,
    to: StorageKeys.tunerTuning,
  ),
  RenameKeyMigration.stringList(
    version: 13,
    id: 'r06.favorite_chords',
    from: LegacyStorageKeys.favoriteChords,
    to: StorageKeys.favoriteChords,
  ),
  RenameKeyMigration.boolean(
    version: 14,
    id: 'r06.metronome_muted',
    from: LegacyStorageKeys.metronomeMuted,
    to: StorageKeys.metronomeMuted,
  ),
  RenameKeyMigration.number(
    version: 15,
    id: 'r06.practice_speed',
    from: LegacyStorageKeys.practiceSpeed,
    to: StorageKeys.practiceSpeed,
  ),
  RenameKeyMigration.integer(
    version: 16,
    id: 'r06.daily_goal_minutes',
    from: LegacyStorageKeys.dailyGoalMinutes,
    to: StorageKeys.dailyGoalMinutes,
  ),
  WrapJsonDocumentMigration(
    version: 17,
    id: 'r07.library_sessions',
    from: LegacyStorageKeys.librarySessions,
    to: StorageKeys.librarySessions,
    shape: JsonBodyShape.list,
  ),
  WrapJsonDocumentMigration(
    version: 18,
    id: 'r07.songs',
    from: LegacyStorageKeys.songs,
    to: StorageKeys.songs,
    shape: JsonBodyShape.list,
  ),
  WrapJsonDocumentMigration(
    version: 19,
    id: 'r07.setlists',
    from: LegacyStorageKeys.setlists,
    to: StorageKeys.setlists,
    shape: JsonBodyShape.list,
  ),
  WrapJsonDocumentMigration(
    version: 20,
    id: 'r07.practice_log',
    from: LegacyStorageKeys.practiceLog,
    to: StorageKeys.practiceLog,
    shape: JsonBodyShape.list,
  ),
  WrapJsonDocumentMigration(
    version: 21,
    id: 'r07.lesson_progress',
    from: LegacyStorageKeys.lessonProgress,
    to: StorageKeys.lessonProgress,
    shape: JsonBodyShape.object,
    bodyKey: 'data',
  ),
  WrapJsonDocumentMigration(
    version: 22,
    id: 'r07.streak',
    from: LegacyStorageKeys.streak,
    to: StorageKeys.streak,
    shape: JsonBodyShape.object,
    bodyKey: 'data',
  ),
  // 23 (ADR 0583) repairs the VALUES 1–22 moved: an epoch day written east of
  // UTC is one short of the true day. It runs last, because it rewrites the
  // namespaced documents that 20 and 22 create — and it is ONE step covering
  // both of them, because a single reading of the device's UTC offset has to
  // decide both: split into two versions, a write failure between them could be
  // retried on a later boot, after the device had crossed UTC, and leave the
  // streak and the practice log a day apart from each other.
  EpochDayShiftMigration(
    version: 23,
    id: 'r-c1.epoch_day_shift',
    documents: [
      EpochDayDocument(
        key: StorageKeys.streak,
        shape: JsonBodyShape.object,
        bodyKey: 'data',
        // `StreakData.lastPracticeDay`. Also the source of gamification's
        // `StreakState.lastQualifiedDay` (`LegacyStreakMigrator` reads this
        // very document), so one repair serves both readers. The record carries
        // no write timestamp, so the shift is the device-offset guess.
        fields: ['last'],
      ),
      EpochDayDocument(
        key: StorageKeys.practiceLog,
        shape: JsonBodyShape.list,
        // `PracticeEntry.day`, which is what `PracticeStats.lastDays` rolls
        // into the `DayTotal`s the weekly chart renders. `PracticeEntry`
        // persists no timestamp either (`day`/`src`/`sec`/`str`/`chd`/`dir`).
        fields: ['day'],
      ),
    ],
  ),
];
