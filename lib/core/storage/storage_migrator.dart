import '../foundation/app_failure.dart';
import '../logging/app_logger.dart';
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
/// Empty by design in E01-R05: this round ships the mechanism, while the keys
/// themselves stay where the shipped builds put them. A feature is renamed to
/// its [StorageKeys] entry in the same round that moves it onto
/// [KeyValueStore] (Kör 6–7) — renaming a key while its owner still reads the
/// old one would lose the user's data.
const List<StorageMigration> appStorageMigrations = [];
