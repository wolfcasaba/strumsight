import 'dart:convert';

import '../foundation/app_failure.dart';
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
/// the owner still reads the old key would lose the user's data.
///
/// One version per key, rather than one bulk step: a run interrupted after the
/// eighth rename resumes at the ninth instead of replaying eight no-ops.
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
];
