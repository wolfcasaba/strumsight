/// File-backed checkpoint marker for the legacy → V2 analysis
/// migration (ADR 0239 §Döntés 9, E06-R21 brief §5.5).
///
/// The store lives in `lib/features/audio_analysis/data/migration/` —
/// a data-layer file. It uses the same atomic temp + flush + verify +
/// rename pattern as the file-analysis repository (its sibling in
/// `local/`) so the marker cannot be partially written. A crash
/// between a successful migration and the marker write simply makes
/// the migrator redo the migration on the next run — the V2 store is
/// idempotent under `document.id` collision.
library;

import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

/// Re-export the file-analysis repository's layout constant so the
/// marker file lives at the canonical location. This avoids a second
/// `analysis_migrationDirectory` constant drifting from the
/// repository's layout contract.
const String analysisMigrationDirectory = 'migration';
const String analysisMigrationStateFileName = 'state.json';

/// Reserved subdirectory inside the analysis-root that owns the
/// migration marker file. The directory is created lazily by [open]
/// and never touched by the file repository itself.
@visibleForTesting
File analysisMigrationStateFileFor(Directory root) {
  return File(
    '${root.path}/$analysisMigrationDirectory/$analysisMigrationStateFileName',
  );
}

/// Immutable checkpoint payload for the migration marker.
@immutable
final class AnalysisMigrationCheckpoint {
  const AnalysisMigrationCheckpoint({
    required this.completedLegacyIds,
    required this.completed,
    this.completedAt,
  });

  /// The legacy ids that have been successfully migrated to V2. The
  /// migrator consults this set on every run to skip already-done
  /// records — the partial-resume invariant the brief §6 cell (5)
  /// covers.
  final Set<String> completedLegacyIds;

  /// `true` once every legacy record present in the V1 store has
  /// been migrated at least once. A `false` marker does NOT mean
  /// the migration failed — it only means the last run did not
  /// reach the end (the migrator is invoked lazily).
  final bool completed;

  /// UTC timestamp of the last successful completion. Null while
  /// [completed] is still false.
  final DateTime? completedAt;

  factory AnalysisMigrationCheckpoint.empty() =>
      const AnalysisMigrationCheckpoint(
        completedLegacyIds: <String>{},
        completed: false,
      );
}

/// Load outcome the migrator branches on. Mirrors the song_trainer
/// `SongMigrationCheckpointLoad` sealed type.
sealed class AnalysisMigrationCheckpointLoad {
  const AnalysisMigrationCheckpointLoad();
}

final class AnalysisMigrationCheckpointLoaded
    extends AnalysisMigrationCheckpointLoad {
  const AnalysisMigrationCheckpointLoaded(this.checkpoint);
  final AnalysisMigrationCheckpoint checkpoint;
}

final class AnalysisMigrationCheckpointMissing
    extends AnalysisMigrationCheckpointLoad {
  const AnalysisMigrationCheckpointMissing();
}

final class AnalysisMigrationCheckpointCorrupt
    extends AnalysisMigrationCheckpointLoad {
  const AnalysisMigrationCheckpointCorrupt();
}

/// File-backed, atomic [AnalysisMigrationCheckpoint] persistence.
///
/// Constructed via [open]; production wires one per analysis-root
/// resolution.
final class AnalysisMigrationVersionStore {
  AnalysisMigrationVersionStore._({
    required this.file,
    required this.stagingDirectory,
  });

  /// Path of the marker file on disk.
  final File file;

  /// Directory the atomic writer stages into.
  final Directory stagingDirectory;

  /// Open a version store for [analysisRoot]. Creates the migration
  /// subdirectory and the analysis-root `temp/` staging directory if
  /// either is missing.
  factory AnalysisMigrationVersionStore.open({
    required Directory analysisRoot,
  }) {
    final migrationDir = Directory(
      '${analysisRoot.path}/$analysisMigrationDirectory',
    )..createSync(recursive: true);
    final stagingDir = Directory(
      '${analysisRoot.path}/${AnalysisMigrationVersionStore._tempDirectory}',
    )..createSync(recursive: true);
    return AnalysisMigrationVersionStore._(
      file: File('${migrationDir.path}/$analysisMigrationStateFileName'),
      stagingDirectory: stagingDir,
    );
  }

  static const String _tempDirectory = 'temp';

  /// Load the current checkpoint from disk. The migrator MUST branch
  /// on the three cases — a missing or corrupt marker both produce
  /// an empty working checkpoint.
  AnalysisMigrationCheckpointLoad load() {
    if (!file.existsSync()) {
      return const AnalysisMigrationCheckpointMissing();
    }
    final Map<String, dynamic> decoded;
    try {
      final raw = file.readAsBytesSync();
      final parsed = jsonDecode(utf8.decode(raw));
      if (parsed is! Map<String, dynamic>) {
        return const AnalysisMigrationCheckpointCorrupt();
      }
      decoded = parsed;
    } catch (_) {
      return const AnalysisMigrationCheckpointCorrupt();
    }
    final schema = decoded['schemaVersion'];
    if (schema is! int || schema != 1) {
      return const AnalysisMigrationCheckpointCorrupt();
    }
    final completedFlag = decoded['completed'];
    if (completedFlag is! bool) {
      return const AnalysisMigrationCheckpointCorrupt();
    }
    final completedAtRaw = decoded['completedAt'];
    final completedAt = switch (completedAtRaw) {
      null => null,
      final String value => DateTime.tryParse(value),
      _ => null,
    };
    final completedIds = _readStringSet(decoded['completedLegacyIds']);
    return AnalysisMigrationCheckpointLoaded(
      AnalysisMigrationCheckpoint(
        completedLegacyIds: completedIds,
        completed: completedFlag,
        completedAt: completedAt,
      ),
    );
  }

  /// Persist [checkpoint] to disk atomically. Uses the song_trainer
  /// `AtomicFileWriter` shape: stage to `temp/`, flush, verify, then
  /// rename onto the marker. On verifier failure the marker is left
  /// untouched and the exception bubbles.
  void save(AnalysisMigrationCheckpoint checkpoint) {
    final payload = <String, Object?>{
      'schemaVersion': 1,
      'completed': checkpoint.completed,
      'completedAt': checkpoint.completedAt?.toUtc().toIso8601String(),
      'completedLegacyIds': checkpoint.completedLegacyIds.toList()..sort(),
    };
    final bytes = utf8.encode(jsonEncode(payload));
    final staging = File(
      '${stagingDirectory.path}${Platform.pathSeparator}'
      'migration-state.tmp-1-${DateTime.now().microsecondsSinceEpoch}',
    );
    staging.writeAsBytesSync(bytes, flush: true);
    // Verify: the bytes must round-trip through jsonDecode with the
    // expected schemaVersion.
    bool verifierPassed;
    try {
      final verified = staging.readAsBytesSync();
      final parsed = jsonDecode(utf8.decode(verified));
      verifierPassed =
          parsed is Map<String, dynamic> && parsed['schemaVersion'] == 1;
    } catch (_) {
      verifierPassed = false;
    }
    if (!verifierPassed) {
      try {
        if (staging.existsSync()) staging.deleteSync(recursive: false);
      } on FileSystemException {
        // Best-effort cleanup.
      }
      throw const FileSystemException(
        'Atomic migration-marker write refused to commit.',
      );
    }
    try {
      staging.renameSync(file.path);
    } on FileSystemException {
      if (file.existsSync()) {
        file.deleteSync(recursive: false);
      }
      staging.renameSync(file.path);
    }
    if (staging.existsSync()) {
      try {
        staging.deleteSync(recursive: false);
      } on FileSystemException {
        // Best-effort.
      }
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

// Re-export the AtomicFileWriter temp-extension symbol so the marker
// write shares a single .tmp sentinel across the feature. The constant
// is taken from the song_trainer reference shape so future cross-feature
// hoisting can swap it without touching call sites.
const String kAnalysisAtomicTempExtension = '.tmp';
