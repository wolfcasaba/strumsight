// Riverpod wiring for the Analysis V2 repository (E06-R21, ADR 0239).
//
// This file is the SINGLE boundary that resolves the production
// filesystem location for the analysis repository: a subdirectory of
// `getApplicationSupportDirectory()` (the platform's only native
// "documents" directory on both iOS and Android). Test code never
// touches `path_provider` — it injects a custom `Directory Function()`
// via the root-resolver override (the song_trainer pattern, ADR 0090
// §Döntés 1 + §5).
//
// Forbidden under the brief §4 allow-list: cross-feature imports, any
// UI/storage plugin beyond `path_provider`. All other dependencies
// are owned by the data/domain layer.

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider/path_provider.dart';

import '../data/local/file_analysis_repository.dart';
import '../data/migration/analysis_migration_version_store.dart';
import '../data/migration/legacy_library_migrator.dart';
import '../domain/analysis_repository.dart';
import '../../../core/storage/storage_keys.dart';
import '../../library/public.dart' show AnalyzedSession;

/// Sub-directory inside the app-support directory that owns the
/// analysis tree. The directory MUST exist before
/// [FileAnalysisRepository.openAtDirectory] opens it; the providers
/// below create it lazily.
const String analysisRepositoryRootDirectoryName = 'analysis';

/// Factory that resolves the production `analysis/` directory by
/// asking `path_provider` for the app-support directory. Test code
/// overrides the provider with a `Directory Function()` returning a
/// temp path.
typedef AnalysisRepositoryRootResolver = Future<Directory> Function();

/// Production-only root resolver — tests override this provider to
/// inject a temp directory in place of `path_provider`.
final analysisRepositoryProductionRootResolverProvider =
    Provider<AnalysisRepositoryRootResolver>((_) => _defaultRootResolver);

Future<Directory> _defaultRootResolver() async {
  final appSupport = await getApplicationSupportDirectory();
  return Directory('${appSupport.path}/$analysisRepositoryRootDirectoryName');
}

/// Override point for the [AnalysisRepository]. Tests provide an
/// `InMemoryAnalysisRepository` or a `FileAnalysisRepository` whose
/// directory has been swapped; production wires it via the boot
/// provider below.
final analysisRepositoryProvider = Provider<AnalysisRepository>((ref) {
  throw StateError(
    'analysisRepositoryProvider must be overridden by the bootstrap layer '
    'before the rest of the app reads it. Tests override directly; '
    'production wires via analysisRepositoryBootProvider.',
  );
});

/// Future-opening variant used by the bootstrap path. The bootstrap
/// produces an [AnalysisRepository] from the resolved directory, then
/// assigns the result to [analysisRepositoryProvider] via
/// `ref.read(analysisRepositoryProvider.notifier) = ...`.
final analysisRepositoryBootProvider = FutureProvider<AnalysisRepository>((
  ref,
) async {
  final rootResolver = ref.watch(
    analysisRepositoryProductionRootResolverProvider,
  );
  final clock = ref.watch(analysisRepositoryClockProvider);
  final root = await rootResolver();
  await root.create(recursive: true);
  return FileAnalysisRepository.openAtDirectory(directory: root, clock: clock);
});

/// Provider for the migration-version store. The marker lives at
/// `<analysisRoot>/migration/state.json` (ADR 0239 §Döntés 9) and is
/// written atomically by the store itself.
final analysisMigrationVersionStoreProvider =
    Provider<AnalysisMigrationVersionStore>((ref) {
      throw StateError(
        'analysisMigrationVersionStoreProvider must be overridden by the '
        'bootstrap layer before the migrator runs.',
      );
    });

/// Future-opening variant — see [analysisRepositoryBootProvider].
final analysisMigrationVersionStoreBootProvider =
    FutureProvider<AnalysisMigrationVersionStore>((ref) async {
      final rootResolver = ref.watch(
        analysisRepositoryProductionRootResolverProvider,
      );
      final root = await rootResolver();
      await root.create(recursive: true);
      return AnalysisMigrationVersionStore.open(analysisRoot: root);
    });

/// Provider for the [LegacyLibraryMigrator]. The boot path calls this
/// once; re-runs after the user explicitly retries.
final legacyLibraryMigratorProvider = Provider<LegacyLibraryMigrator>((ref) {
  throw StateError(
    'legacyLibraryMigratorProvider must be overridden by the bootstrap '
    'layer before the migrator runs.',
  );
});

/// Future-opening variant. Wires the production repository, the
/// migration-version store, and the production library repository
/// supplier. Tests override [legacyLibrarySupplierProvider] below to
/// inject a synthetic supplier.
final legacyLibraryMigratorBootProvider = FutureProvider<LegacyLibraryMigrator>(
  (ref) async {
    final repository = await ref.watch(analysisRepositoryBootProvider.future);
    final versionStore = await ref.watch(
      analysisMigrationVersionStoreBootProvider.future,
    );
    final supplier = ref.watch(legacyLibrarySupplierProvider);
    return LegacyLibraryMigrator(
      repository: repository,
      versionStore: versionStore,
      supplier: supplier,
    );
  },
);

/// Supplier the migrator uses to read legacy V1 sessions. The
/// production wiring overrides this provider with a closure that
/// calls into the library feature's `libraryRepositoryProvider.load`
/// (the audio-analysis data layer never imports `LibraryRepository`
/// — the round's `allowed_paths` does not include
/// `lib/features/library/**`). Tests inject a synthetic in-memory
/// list of [AnalyzedSession]s.
final legacyLibrarySupplierProvider = Provider<LegacyLibrarySupplier>(
  (_) => _noLegacySupplier,
);

/// Empty default — the bootstrap layer MUST override this provider
/// before any migrator run is dispatched.
Future<List<AnalyzedSession>> _noLegacySupplier() async =>
    const <AnalyzedSession>[];

/// Production-only clock supplier — tests override this provider to
/// inject a deterministic clock.
final analysisRepositoryClockProvider = Provider<DateTime Function()>(
  (_) => DateTime.now,
);

/// Re-export the StorageKeys migration constant so callers do not
/// need to import the storage layer.
const String analysisMigrationStorageKey = StorageKeys.analysisMigrationState;
