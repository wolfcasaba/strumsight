// A1 — a playback-only Song Trainer session never fabricates a score.
//
// §0.0/B/B2 already measured the domain truth: `isPlaybackOnly` is decided
// by `SongPracticeCompilation.playbackOnly()` (no `PracticeDefinition`), and
// `SongTrainerController` never populates `SongTrainerState.result` for a
// playback-only run (`finish()` skips `_finishAndFinalize`, which is the only
// place that ever sets `result`). This round's job is to SURFACE that
// honestly on the Stage completed state instead of leaving an ambiguous
// "Completed" label — and never to invent a percentage.
//
// §6.1 mérce-mátrix: a fabricated score on this branch must turn this file's
// tests RED.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_practice_compiler.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_trainer_controller.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_trainer_state.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_transport.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_transport_clock.dart';
import 'package:strumsight/features/song_trainer/data/playback/fake_backing_audio_player.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_asset_reference.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/song_trainer_screen.dart';
import 'package:strumsight/features/song_trainer/presentation/widgets/measure_heatmap.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/core/design_system/public.dart' show SsLightTheme;

import '../../../support/preference_store.dart';

void main() {
  testWidgets(
    'A1: a completed playback-only session states honestly that it was not '
    'scored, and shows no heatmap or percentage',
    (tester) async {
      final player = FakeBackingAudioPlayer();
      final transport = SongTransport(
        player: player,
        clock: FakeSongTransportClock(),
      );
      final controller = SongTrainerController(
        transport: transport,
        compilation: const SongPracticeCompilation.playbackOnly(),
        backingAsset: _asset,
      );
      addTearDown(() async {
        await controller.dispose();
        await transport.dispose();
      });

      expect(controller.isPlaybackOnly, isTrue);
      await controller.prepare();
      await controller.start();
      await controller.finish();

      // The domain never produced a result for this branch — the fixture
      // itself proves the premise this test guards.
      expect(controller.state.status, SongTrainerStatus.completed);
      expect(controller.state.result, isNull);

      await tester.pumpWidget(
        ProviderScope(
          overrides: preferenceOverrides(),
          child: MaterialApp(
            theme: SsLightTheme.data(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: SongTrainerScreen(state: controller.state),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const Key('song-trainer-playback-only-result')),
        findsOneWidget,
      );
      // No fabricated score surface of any kind.
      expect(find.byType(MeasureHeatmap), findsNothing);
      expect(find.textContaining('%'), findsNothing);
    },
  );
}

final SongAssetReference _asset = SongAssetReference(
  id: SongAssetId('backing'),
  sha256: 'a' * 64,
  extension: 'mp3',
  byteLength: 100,
  mimeType: 'audio/mpeg',
  durationMs: 60000,
);
