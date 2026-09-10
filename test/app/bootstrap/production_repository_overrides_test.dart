// E18-R01 emulator finding F5 — `Profile → Library` failed on every device
// ("Couldn't load your library") because production wired only the song
// store; `analysisRepositoryProvider` and `setlistRepositoryProvider` kept
// their deliberate `throw`. Every widget test overrode the sources, so the
// suite was blind. This cell builds the REAL production override list (with
// the `path_provider` roots swapped for temp directories) and reads the real
// `libraryV2SourcesProvider` + controller through it.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/bootstrap/production_repository_overrides.dart';
import 'package:strumsight/features/audio_analysis/application/analysis_providers.dart';
import 'package:strumsight/features/library_v2/providers/library_v2_providers.dart';
import 'package:strumsight/features/song_trainer/application/song_trainer_providers.dart';
import 'package:strumsight/features/song_trainer/data/local/in_memory_song_repository.dart';

import '../../support/preference_store.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('strumsight-prod-overrides-');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('the production override list makes the unified Library\'s sources '
      'readable — no "must be overridden" StateError', () async {
    final bootstrap = ProviderContainer(
      overrides: [
        analysisRepositoryProductionRootResolverProvider.overrideWithValue(
          () async => Directory('${root.path}/analysis'),
        ),
        songTrainerProductionRootResolverProvider.overrideWithValue(
          () async => Directory('${root.path}/songs'),
        ),
      ],
    );
    addTearDown(bootstrap.dispose);

    final overrides = await buildProductionRepositoryOverrides(bootstrap);
    expect(overrides, hasLength(2));

    final app = ProviderContainer(
      overrides: [
        ...preferenceOverrides(),
        songRepositoryProvider.overrideWithValue(
          InMemorySongRepository(clock: DateTime.now),
        ),
        ...overrides,
      ],
    );
    addTearDown(app.dispose);

    // The exact read that threw on the device.
    final sources = app.read(libraryV2SourcesProvider);
    expect(sources, hasLength(4));

    // …and the controller that swallowed it into an AsyncError.
    final items = await app.read(libraryV2ItemsProvider.future);
    expect(items, isEmpty);
    expect(app.read(libraryV2ItemsProvider).hasError, isFalse);
  });

  test('WITHOUT the production overrides the same read fails — the guard is '
      'not vacuous', () {
    final app = ProviderContainer(
      overrides: [
        ...preferenceOverrides(),
        songRepositoryProvider.overrideWithValue(
          InMemorySongRepository(clock: DateTime.now),
        ),
      ],
    );
    addTearDown(app.dispose);

    // Riverpod wraps the provider's StateError in its own ProviderException;
    // the contract under test is "it throws", the positive cell above is
    // the proof that the override list makes it stop.
    expect(() => app.read(libraryV2SourcesProvider), throwsA(anything));
  });
}
