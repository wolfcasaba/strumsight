/// Atomic, file-based persistence for the migration checkpoint and
/// completion marker (E03-R08, ADR 0117 §Döntés 2, SDD §18.6).
///
/// The version store lives in `lib/features/song_trainer/data/migration/`
/// (a data-layer file — see the round's §4 list). It reuses the
/// already-shipped [AtomicFileWriter] from R07 so the same temp→flush→
/// verify→rename atomicity guarantee the song / asset repositories
/// enjoy also covers the migration marker — a crash between a song
/// write and the marker write cannot leave a stale `completed: true` on
/// disk.
///
/// The store deals in a [SongMigrationCheckpoint] value object only. It
/// never imports a Riverpod provider, a Flutter binding, or
/// `SharedPreferences`. The production provider in
/// `application/song_trainer_providers.dart` wires a concrete
/// implementation by passing the songs root.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../../application/migration/song_migration_state.dart';
import '../local/atomic_file_writer.dart';

/// Reserved subdirectory inside the songs-root that owns the migration
/// marker file. The directory is created lazily by [open] and never
/// touched by the song repository itself.
const String songMigrationDirectoryName = 'migration';

/// File name of the migration marker. Versioned by name so a future
/// shape change can live next to it without overwriting the user's
/// current checkpoint.
const String songMigrationStateFileName = 'state.json';

/// Stable machine-readable codes the [SongMigrationVersionStore] can
/// emit. The list is intentionally tiny: the store either succeeds or
/// hits a known platform failure mode.
abstract final class SongMigrationVersionStoreErrorCode {
  /// The platform refused to read or write the marker file.
  static const String io = 'songMigration.versionStore.io';

  /// The marker file exists but its JSON shape is unrecognised — either
  /// the schema version is newer than this build understands or the
  /// JSON is structurally invalid. The migrator MUST treat this as
  /// "no checkpoint exists yet" so a future version never silently
  /// downgrades a real completion.
  static const String corrupt = 'songMigration.versionStore.corrupt';
}

/// Result envelope returned by [SongMigrationVersionStore.load] — the
/// store either has a real checkpoint on disk or it has no marker yet
/// (a fresh install). A corrupt marker is a third, observable state so
/// the migrator can record the failure rather than silently downgrading.
sealed class SongMigrationCheckpointLoad {
  const SongMigrationCheckpointLoad();
}

/// A valid checkpoint was loaded from disk. Always carries a non-null
/// [checkpoint].
final class SongMigrationCheckpointLoaded extends SongMigrationCheckpointLoad {
  const SongMigrationCheckpointLoaded(this.checkpoint);
  final SongMigrationCheckpoint checkpoint;
}

/// The marker file does not exist yet. The migrator starts from an
/// empty checkpoint.
final class SongMigrationCheckpointMissing extends SongMigrationCheckpointLoad {
  const SongMigrationCheckpointMissing();
}

/// The marker file exists but its contents are unrecognised (corrupt
/// JSON, future schema version, missing required field). The migrator
/// records the failure and starts from an empty checkpoint so the user
/// is never silently regressed.
final class SongMigrationCheckpointCorrupt extends SongMigrationCheckpointLoad {
  const SongMigrationCheckpointCorrupt();
}

/// File-based, atomic [SongMigrationCheckpoint] persistence.
///
/// A new instance MUST be obtained via [SongMigrationVersionStore.open] —
/// the factory ensures the migration subdirectory exists before the
/// first write.
final class SongMigrationVersionStore {
  SongMigrationVersionStore._({
    required this.file,
    required this.writer,
    required this.stagingDirectory,
  });

  /// Path of the marker file on disk.
  final File file;

  /// Atomic writer reused across runs.
  final AtomicFileWriter writer;

  /// Directory inside the songs-root `temp/` the writer stages into.
  final Directory stagingDirectory;

  /// Open a version store for [songsRoot]. Creates the migration
  /// subdirectory and the songs-root `temp/` staging directory if
  /// either is missing. The store is cheap; production wires one per
  /// provider resolution.
  factory SongMigrationVersionStore.open({
    required Directory songsRoot,
    AtomicFileWriter writer = const AtomicFileWriter(),
  }) {
    final migrationDir = Directory(
      '${songsRoot.path}/$songMigrationDirectoryName',
    )..createSync(recursive: true);
    final stagingDir = Directory('${songsRoot.path}/temp')
      ..createSync(recursive: true);
    return SongMigrationVersionStore._(
      file: File('${migrationDir.path}/$songMigrationStateFileName'),
      writer: writer,
      stagingDirectory: stagingDir,
    );
  }

  /// Load the current checkpoint from disk.
  ///
  /// Returns:
  ///   - [SongMigrationCheckpointLoaded] with a real [SongMigrationCheckpoint]
  ///     when the marker file exists and decodes cleanly;
  ///   - [SongMigrationCheckpointMissing] when no marker file exists yet;
  ///   - [SongMigrationCheckpointCorrupt] when the marker file is present
  ///     but undecodable.
  ///
  /// The migrator MUST branch on the three cases — a missing or corrupt
  /// marker both produce an empty working checkpoint.
  SongMigrationCheckpointLoad load() {
    if (!file.existsSync()) {
      return const SongMigrationCheckpointMissing();
    }
    final Map<String, dynamic> decoded;
    try {
      final raw = file.readAsBytesSync();
      final parsed = jsonDecode(utf8.decode(raw));
      if (parsed is! Map<String, dynamic>) {
        return const SongMigrationCheckpointCorrupt();
      }
      decoded = parsed;
    } catch (_) {
      return const SongMigrationCheckpointCorrupt();
    }
    final schema = decoded['schemaVersion'];
    if (schema is! int || schema != 1) {
      return const SongMigrationCheckpointCorrupt();
    }
    final completedFlag = decoded['completed'];
    if (completedFlag is! bool) {
      return const SongMigrationCheckpointCorrupt();
    }
    final completedAtRaw = decoded['completedAt'];
    final completedAt = switch (completedAtRaw) {
      null => null,
      final String value => DateTime.tryParse(value),
      _ => null,
    };
    final completedIds = _readStringSet(decoded['completedIds']);
    final redactedIds = _readStringSet(decoded['redactedIds']);
    return SongMigrationCheckpointLoaded(
      SongMigrationCheckpoint(
        completedLegacySongIds: completedIds,
        redactedLegacySongIds: redactedIds,
        completed: completedFlag,
        completedAt: completedAt,
      ),
    );
  }

  /// Persist [checkpoint] to disk atomically.
  ///
  /// Uses the same staged-write + verify + rename pipeline as the song
  /// repository so the marker can never be partially written. On a
  /// verifier failure or a write refusal, the marker is left untouched
  /// and the exception bubbles — the migrator treats this as a transient
  /// IO failure (records this run's data in memory, surfaces the failure
  /// to the outcome, retries on the next run).
  Future<void> save(SongMigrationCheckpoint checkpoint) async {
    final payload = <String, dynamic>{
      'schemaVersion': 1,
      'completed': checkpoint.completed,
      'completedAt': checkpoint.completedAt?.toUtc().toIso8601String(),
      'completedIds': checkpoint.completedLegacySongIds.toList()..sort(),
      'redactedIds': checkpoint.redactedLegacySongIds.toList()..sort(),
    };
    final bytes = utf8.encode(jsonEncode(payload));
    final outcome = writer.write(
      target: file,
      bytes: Uint8List.fromList(bytes),
      stagingDirectory: stagingDirectory,
      verifier: (Uint8List verified) {
        // The verifier round-trips the bytes through the same codec so
        // a partial write cannot land as the committed marker.
        final parsed = jsonDecode(utf8.decode(verified));
        if (parsed is! Map<String, dynamic>) return false;
        return parsed['schemaVersion'] == 1;
      },
    );
    if (!outcome.committed) {
      throw const FileSystemException(
        'AtomicFileWriter refused to commit the migration marker.',
      );
    }
  }

  static Set<String> _readStringSet(Object? raw) {
    if (raw is! List) return const <String>{};
    final out = <String>{};
    for (final entry in raw) {
      if (entry is String && entry.isNotEmpty) out.add(entry);
    }
    return out;
  }
}

/// Test-only exposed factory — exposes the constructed [File] path so
/// tests can hand-construct a store with a pre-existing songs-root and
/// assert on the underlying file path. Production code MUST use
/// [SongMigrationVersionStore.open].
@visibleForTesting
File songMigrationStateFileFor(Directory songsRoot) {
  return File(
    '${songsRoot.path}/$songMigrationDirectoryName/$songMigrationStateFileName',
  );
}
