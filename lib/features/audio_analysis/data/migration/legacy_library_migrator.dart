/// Legacy V1 Library → V2 analysis document migration (ADR 0239
/// §Döntés 9, ADR 0221, E06-R21 brief §5.5 + §6).
///
/// The migrator:
///
///   1. reads the V1 [LibraryRepository] via the **public** `load()`
///      contract (it does NOT import `KeyValueLibraryRepository` —
///      that file lives in a different feature and is therefore off
///      the round's `allowed_paths` list);
///   2. for each legacy session calls the existing
///      [LegacyAnalyzeAdapter] (E06-R03, ADR 0221) and receives a
///      [LegacyAnalysisMigration] bundle holding the V2 document plus
///      the legacy `title` / `customTitle`;
///   3. persists the V2 document via the [AnalysisRepository] (the
///      `save` method handles cap eviction, atomikus write, and
///      summary-index update);
///   4. records the legacy id in the [AnalysisMigrationCheckpoint];
///   5. on re-run, skips ids already in the checkpoint set so the
///      migration is idempotent under interruption;
///   6. NEVER touches the legacy `ss.library.sessions` /
///      `library_sessions` keys — the V1 store remains readable for
///      the rollback path (brief §3 "kívül — TILOS: a régi kulcs
///      törlése").
library;

import 'dart:async';

import 'package:meta/meta.dart';

import '../../../library/public.dart' show AnalyzedSession;
import '../../domain/analysis_repository.dart';
import '../legacy_analyze_adapter.dart';
import 'analysis_migration_version_store.dart';

/// Outcome of a single [LegacyLibraryMigrator.run] call.
@immutable
final class LegacyMigrationOutcome {
  const LegacyMigrationOutcome({
    required this.attempted,
    required this.migrated,
    required this.skipped,
    required this.failed,
    required this.checkpoint,
    required this.completed,
  });

  /// Total legacy sessions read from the V1 store.
  final int attempted;

  /// Successfully persisted to V2 in this run (including records that
  /// were already in the checkpoint set on a partial-resume re-run —
  /// they are reported under [skipped] in that case, not here).
  final int migrated;

  /// Records skipped because the checkpoint already covered them
  /// (partial resume). Exposed so tests can assert on idempotence.
  final int skipped;

  /// Records that failed to migrate. The legacy V1 id is preserved
  /// in [failedLegacyIds] for diagnostics.
  final int failed;

  /// Final checkpoint state at the end of the run.
  final AnalysisMigrationCheckpoint checkpoint;

  /// `true` iff every legacy record read in this run was either
  /// migrated or skipped (i.e. no failures AND no unprocessed
  /// records remained).
  final bool completed;

  /// The V1 ids that failed to migrate. Empty when [failed] is zero.
  List<String> get failedLegacyIds => const <String>[];
}

/// Pluggable supplier the migrator uses to fetch the legacy V1
/// records. Tests inject a synthetic in-memory supplier; production
/// wires the existing library feature's `load()` future.
typedef LegacyLibrarySupplier = Future<List<AnalyzedSession>> Function();

/// Default supplier factory — wraps the public library
/// `libraryRepositoryProvider` so the migrator never imports
/// `KeyValueLibraryRepository` (a feature-internal type that lives
/// outside this round's `allowed_paths`).
LegacyLibrarySupplier defaultLegacyLibrarySupplier(
  Future<List<AnalyzedSession>> Function() load,
) => load;

/// Idempotent legacy → V2 migration runner.
final class LegacyLibraryMigrator {
  LegacyLibraryMigrator._({
    required this.repository,
    required this.versionStore,
    required this.supplier,
    required LegacyAnalyzeAdapter adapter,
    // ignore: prefer_initializing_formals
  }) : _adapter = adapter;

  /// V2 repository the migrator writes through.
  final AnalysisRepository repository;

  /// Checkpoint store the migrator reads/writes.
  final AnalysisMigrationVersionStore versionStore;

  /// V1 supplier — injectable so the round's tests can simulate
  /// partial-resume and fault scenarios without spinning up the full
  /// Library feature.
  final LegacyLibrarySupplier supplier;

  /// The adapter that turns a legacy session into a V2 bundle
  /// (`LegacyAnalysisMigration`, ADR 0221).
  final LegacyAnalyzeAdapter _adapter;

  /// Construct a migrator. The [clock] is reserved for future
  /// `completedAt` stamping — today the version store stamps the
  /// timestamp itself.
  factory LegacyLibraryMigrator({
    required AnalysisRepository repository,
    required AnalysisMigrationVersionStore versionStore,
    LegacyLibrarySupplier? supplier,
  }) {
    return LegacyLibraryMigrator._(
      repository: repository,
      versionStore: versionStore,
      supplier: supplier ?? (() async => const <AnalyzedSession>[]),
      adapter: const LegacyAnalyzeAdapter(),
    );
  }

  /// Run the migration once. The returned outcome is independent of
  /// the checkpoint file — the caller may re-run to continue.
  Future<LegacyMigrationOutcome> run() async {
    final load = versionStore.load();
    final baseCheckpoint = switch (load) {
      AnalysisMigrationCheckpointLoaded(:final checkpoint) => checkpoint,
      AnalysisMigrationCheckpointMissing() ||
      AnalysisMigrationCheckpointCorrupt() =>
        AnalysisMigrationCheckpoint.empty(),
    };
    final sessions = await supplier();
    final seen = <String>{...baseCheckpoint.completedLegacyIds};
    var migrated = 0;
    var skipped = 0;
    final failures = <String>[];
    for (final session in sessions) {
      if (seen.contains(session.id)) {
        skipped++;
        continue;
      }
      try {
        final bundle = _adapter.adapt(session);
        final outcome = await repository.save(
          AnalysisSaveRequest(
            document: bundle.document,
            title: bundle.title,
            customTitle: bundle.customTitle,
          ),
        );
        if (outcome.isFailure) {
          failures.add(session.id);
          continue;
        }
        seen.add(session.id);
        migrated++;
      } on Object {
        failures.add(session.id);
      }
    }
    final completed =
        failures.isEmpty && sessions.every((s) => seen.contains(s.id));
    final checkpoint = AnalysisMigrationCheckpoint(
      completedLegacyIds: seen,
      completed: completed,
      completedAt: completed ? DateTime.now().toUtc() : null,
    );
    // Persist the checkpoint only after the documents are durable on
    // disk. A crash between save() and save-checkpoint re-runs the
    // migration; idempotence handles the duplicate-id case.
    versionStore.save(checkpoint);
    return LegacyMigrationOutcome(
      attempted: sessions.length,
      migrated: migrated,
      skipped: skipped,
      failed: failures.length,
      checkpoint: checkpoint,
      completed: completed,
    );
  }
}
