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

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider/path_provider.dart';

import '../data/local/file_song_asset_repository.dart';
import '../data/local/file_song_repository.dart';
import '../data/local/in_memory_song_repository.dart';
import '../data/local/song_repository_recovery.dart';
import '../domain/repositories/song_asset_repository.dart';
import '../domain/repositories/song_repository.dart';

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
