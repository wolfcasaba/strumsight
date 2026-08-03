// Riverpod wiring for the Song Trainer V2 repositories (E03-R07,
// ADR 0090 §Döntés 1 + §Döntés 5, SDD §18.2).
//
// This file is the SINGLE boundary that resolves the production
// filesystem location for the song repositories: a subdirectory of
// `getApplicationSupportDirectory()` (the platform's only native
// "documents" directory on both iOS and Android). Test code never
// touches `path_provider` — it injects a custom `Directory` via the
// `Directory Function()` factory below.
//
// Forbidden under AGENTS.md §7 / R07 brief: SharedPreferences, GoRouter,
// Navigator, BuildContext, or any storage plugin beyond `path_provider`.
// All other dependencies are owned by the data layer.

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider/path_provider.dart';

import '../../../core/logging/logger_provider.dart';
import '../../../core/storage/key_value_store.dart';
import '../../../core/storage/storage_providers.dart';
import 'import/song_import_controller.dart';
import 'import/song_import_state.dart';
import '../data/importers/importer_registry.dart';
import '../data/importers/native_json_importer.dart';
import '../data/importers/musicxml_importer.dart';
import '../data/importers/midi_importer.dart';
import '../data/importers/mxl_importer.dart';
import '../data/importers/song_importer.dart';
import '../data/local/file_song_asset_repository.dart';
import '../data/local/file_song_repository.dart';
import '../data/local/in_memory_song_repository.dart';
import '../data/local/song_repository_recovery.dart';
import '../data/migration/song_migration_version_store.dart';
import '../domain/repositories/song_asset_repository.dart';
import '../domain/repositories/song_repository.dart';
import 'migration/song_migration_state.dart';
import 'migration/song_storage_migrator.dart';

/// Sub-directory inside the app-support directory that owns the
/// song tree. The directory MUST exist before [FileSongRepository]
/// opens it; the providers below create it lazily.
const String songTrainerRootDirectoryName = 'songs';

/// Factory that resolves the production `songs/` directory by asking
/// `path_provider` for the app-support directory. Test code overrides
/// the provider with a `Directory Function()` returning a temp path.
typedef SongTrainerRootResolver = Future<Directory> Function();

/// Clock supplier — production wires to `DateTime.now`. Tests inject a
/// fixed clock for determinism.
typedef ClockSupplier = DateTime Function();

const ClockSupplier _productionClock = DateTime.now;

/// Production-only root resolver — tests override this provider to
/// inject a temp directory in place of `path_provider`.
final songTrainerProductionRootResolverProvider =
    Provider<SongTrainerRootResolver>((_) => _defaultRootResolver);

/// Production-only clock — tests override this provider to inject
/// a deterministic clock.
final songTrainerClockProvider = Provider<ClockSupplier>(
  (_) => _productionClock,
);

/// Default resolver: `Directory('${appSupport}/songs')`.
///
/// `path_provider` is required because the song tree MUST be reachable
/// across process restarts AND capable of holding multi-megabyte
/// binary payloads — neither constraint matches SharedPreferences'
/// design (ADR 0090 §Döntés 1).
Future<Directory> _defaultRootResolver() async {
  final appSupport = await getApplicationSupportDirectory();
  return Directory('${appSupport.path}/$songTrainerRootDirectoryName');
}

/// Provider for the production song repository. Resolves the song
/// tree's directory on first read and reuses a single
/// [FileSongRepository] instance across the app's lifetime.
///
/// Override this provider in widget tests with [InMemorySongRepository]
/// to avoid pulling `path_provider` into the test process.
final songRepositoryProvider = Provider<SongRepository>((ref) {
  throw StateError(
    'songRepositoryProvider must be overridden by the bootstrap layer '
    'before the rest of the app reads it. Tests override with '
    'InMemorySongRepository; production wires via songRepositoryBootProvider.',
  );
});

/// Future-opening variant used by the bootstrap path. The bootstrap
/// produces a [SongRepository] from the resolved directory and clock,
/// then assigns the result to [songRepositoryProvider] via
/// `ref.read(songRepositoryProvider.notifier) = ...` (Riverpod 3
/// provider mutator pattern).
///
/// Exposed as a separate provider so widget tests can ignore it
/// entirely and override the synchronous [songRepositoryProvider]
/// directly.
final songRepositoryBootProvider = FutureProvider<SongRepository>((ref) async {
  final rootResolver = ref.watch(songTrainerProductionRootResolverProvider);
  final clock = ref.watch(songTrainerClockProvider);
  final root = await rootResolver();
  await root.create(recursive: true);
  // Run a startup recovery scan in `no-action` mode so the boot
  // path records available residue without touching user content.
  await SongRepositoryRecovery.scan(root);
  return FileSongRepository.openAtDirectory(directory: root, clock: clock);
});

/// Provider for the production asset store. Mirrors [songRepositoryProvider].
final songAssetRepositoryProvider = Provider<SongAssetRepository>((ref) {
  throw StateError(
    'songAssetRepositoryProvider must be overridden by the bootstrap layer '
    'before the rest of the app reads it.',
  );
});

/// Future-opening variant — see [songRepositoryBootProvider].
final songAssetRepositoryBootProvider = FutureProvider<SongAssetRepository>((
  ref,
) async {
  final rootResolver = ref.watch(songTrainerProductionRootResolverProvider);
  final clock = ref.watch(songTrainerClockProvider);
  final root = await rootResolver();
  return FileSongAssetRepository.openAtDirectory(root: root, clock: clock);
});

/// In-memory override consumed by widget tests. The bootstrap layer
/// never assigns to this provider — it is purely a test-helper.
final inMemorySongRepositoryProvider = Provider<SongRepository>(
  (_) => InMemorySongRepository(clock: DateTime.now),
);

/// Registry owned by the import application flow. New format importers are
/// appended only after their parser and licence feasibility rounds complete.
final songImporterRegistryProvider = Provider<ImporterRegistry>(
  (_) => const ImporterRegistry(
    importers: <SongImporter>[
      NativeJsonImporter(),
      MusicXmlImporter(),
      MxlImporter(),
      MidiImporter(),
    ],
  ),
);

/// Per-operation temporary root. Its paths never leave the data/application
/// boundary or enter Riverpod state.
final songImportWorkspaceRootProvider = Provider<SongTrainerRootResolver>((
  ref,
) {
  final resolveSongsRoot = ref.watch(songTrainerProductionRootResolverProvider);
  return () async {
    final songsRoot = await resolveSongsRoot();
    return Directory('${songsRoot.path}/import-workspace');
  };
});

/// Application import flow with a bounded registry and operation-owned cleanup.
/// The provider is auto-disposed so route exit cancels and closes the workspace.
final songImportControllerProvider = Provider.autoDispose<SongImportController>(
  (ref) {
    final controller = SongImportController(
      registry: ref.watch(songImporterRegistryProvider),
      repository: ref.watch(songRepositoryProvider),
      workspaceRoot: ref.watch(songImportWorkspaceRootProvider),
    );
    ref.onDispose(() => unawaited(controller.dispose()));
    return controller;
  },
);

/// Reactive import state for presentation consumers. The state itself contains
/// only phase, operation ID, preview metadata and a stable failure code.
final songImportStateProvider = StreamProvider.autoDispose<SongImportState>(
  (ref) => ref.watch(songImportControllerProvider).states,
);

/// Provider for the persistent [SongMigrationVersionStore] — the file-
/// based checkpoint / completion marker under `<songsRoot>/migration/state.json`
/// (E03-R08, ADR 0117 §Döntés 2).
///
/// Reads the songs root from [songTrainerProductionRootResolverProvider] and
/// creates the marker directory lazily. Tests override the root resolver and
/// the clock so the marker file lands under a temp directory.
final songMigrationVersionStoreProvider =
    FutureProvider<SongMigrationVersionStore>((ref) async {
      final rootResolver = ref.watch(songTrainerProductionRootResolverProvider);
      final root = await rootResolver();
      return SongMigrationVersionStore.open(songsRoot: root);
    });

/// Provider for the [SongStorageMigrator] use case (E03-R08, ADR 0117
/// §Döntés 1 + §Döntés 3).
///
/// Wires the production [SongRepository], the production [KeyValueStore]
/// (the same one the `songs` / `setlists` features use), the production
/// clock, and the production logger. The legacy fallback flag
/// ([FeatureFlags.songTrainerV2Enabled]) is honoured by the boot
/// controller — the provider here is the wiring surface, not the
/// rollout gate.
final songStorageMigratorProvider = FutureProvider<SongStorageMigrator>((
  ref,
) async {
  final repository = await ref.watch(songRepositoryBootProvider.future);
  final legacyStore = ref.watch(keyValueStoreProvider);
  final rootResolver = ref.watch(songTrainerProductionRootResolverProvider);
  final clock = ref.watch(songTrainerClockProvider);
  final logger = ref.watch(appLoggerProvider);
  final songsRoot = await rootResolver();
  return SongStorageMigrator.create(
    legacyStore: legacyStore,
    songRepository: repository,
    songsRoot: songsRoot,
    clock: clock,
    logger: logger,
    readBackRepositoryFactory: () =>
        FileSongRepository.openAtDirectory(directory: songsRoot, clock: clock),
  );
});

/// Provider that runs the migration ONCE per provider-container lifetime
/// (E03-R08, ADR 0117).
///
/// The boot path calls this exactly once; subsequent reads return the cached
/// outcome. A persistent restart-safe UI can re-watch it after the user
/// retries — re-running the migrator is safe because the underlying
/// checkpoint guarantees no duplicates.
final songMigrationOutcomeProvider = FutureProvider<SongMigrationOutcome>((
  ref,
) async {
  final migrator = await ref.watch(songStorageMigratorProvider.future);
  return migrator.run();
});
