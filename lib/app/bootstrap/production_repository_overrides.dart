import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import '../../features/audio_analysis/application/analysis_providers.dart';
import '../../features/song_trainer/application/song_trainer_providers.dart';

/// The file-backed repositories the production `ProviderScope` must wire
/// besides the song store: their base providers deliberately `throw` until
/// overridden, and the unified Library reads all of them on its first
/// build (`libraryV2SourcesProvider`).
///
/// Measured on the E18-R01 emulator (finding F5): `main.dart` wired only
/// `songRepositoryProvider`, so `Profile → Library` rendered "Couldn't load
/// your library" on every device, with no console exception — Riverpod
/// captured the `StateError` into the controller's `AsyncError`. Every
/// widget test overrode the sources, so the suite never saw it. The
/// bootstrap reads the `*BootProvider` variants (which resolve the
/// `path_provider` directories) from a throw-away container, exactly as
/// the song store is wired; `test/app/bootstrap/
/// production_repository_overrides_test.dart` reads the real
/// `libraryV2SourcesProvider` through the result.
Future<List<Override>> buildProductionRepositoryOverrides(
  ProviderContainer bootstrapContainer,
) async {
  final analysis = await bootstrapContainer.read(
    analysisRepositoryBootProvider.future,
  );
  final setlists = await bootstrapContainer.read(
    setlistRepositoryBootProvider.future,
  );
  return <Override>[
    analysisRepositoryProvider.overrideWithValue(analysis),
    setlistRepositoryProvider.overrideWithValue(setlists),
  ];
}
