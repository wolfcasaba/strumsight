// A5 — a setlist's upcoming tuning/capo changes are announced BEFORE the run
// starts, not discovered only once the affected song begins (§5.4).
// A7 — leaving the Stage disposes the owning controller on every exit path
// (§5.6, §0.0/B/B7): the presentation layer does not acquire the resource,
// it notifies the owner's exit path instead of relying only on Riverpod's
// own provider-teardown timing.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/song_trainer/application/song_trainer_providers.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_practice_compiler.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_trainer_controller.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_trainer_state.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_transport.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_transport_clock.dart';
import 'package:strumsight/features/song_trainer/data/playback/fake_backing_audio_player.dart';
import 'package:strumsight/features/song_trainer/domain/models/setlist_result.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_asset_reference.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_setlist.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/setlist_session_screen.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/song_trainer_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/core/design_system/public.dart' show SsLightTheme;

import '../../../support/preference_store.dart';

void main() {
  group('A5 — tuning/capo changes ahead are announced before Start', () {
    testWidgets(
      'a setlist with a tuning and a capo change shows the advisory before '
      'the run starts',
      (tester) async {
        final setlist = SongSetlist(
          id: 'setlist-tuning',
          name: 'Tuning changes',
          createdAt: DateTime.utc(2026, 8, 4),
          updatedAt: DateTime.utc(2026, 8, 4),
          items: <SongSetlistItem>[
            SongSetlistItem(id: 'a', songId: SongId('song-a')),
            SongSetlistItem(
              id: 'b',
              songId: SongId('song-b'),
              overrides: const SetlistItemOverrides(
                tuningOverrideCode: 'dropD',
              ),
            ),
            SongSetlistItem(
              id: 'c',
              songId: SongId('song-c'),
              overrides: const SetlistItemOverrides(capoOverride: 2),
            ),
          ],
        );

        await tester.pumpWidget(
          _localizedApp(
            SetlistSessionScreen(
              setlist: setlist,
              mode: SetlistSessionMode.performance,
              availability: (_) => SetlistItemAvailability.ready,
              performanceRunner: (item) async =>
                  SetlistItemResult.completed(itemId: item.id),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Announced ahead of tapping Start — the control case ("only
        // discovered once the song starts") never renders this before a run.
        final advisory = find.byKey(const Key('setlist-session-tuning-ahead'));
        expect(advisory, findsOneWidget);
        expect(find.textContaining('dropD'), findsWidgets);
        expect(find.byKey(const Key('setlist-session-start')), findsOneWidget);
      },
    );

    testWidgets(
      'a setlist that never changes tuning or capo shows no advisory',
      (tester) async {
        final setlist = SongSetlist(
          id: 'setlist-stable',
          name: 'No changes',
          createdAt: DateTime.utc(2026, 8, 4),
          updatedAt: DateTime.utc(2026, 8, 4),
          items: <SongSetlistItem>[
            SongSetlistItem(id: 'a', songId: SongId('song-a')),
            SongSetlistItem(id: 'b', songId: SongId('song-a')),
          ],
        );

        await tester.pumpWidget(
          _localizedApp(
            SetlistSessionScreen(
              setlist: setlist,
              mode: SetlistSessionMode.performance,
              availability: (_) => SetlistItemAvailability.ready,
              performanceRunner: (item) async =>
                  SetlistItemResult.completed(itemId: item.id),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('setlist-session-tuning-ahead')),
          findsNothing,
        );
      },
    );
  });

  group('A7 — leaving the Stage disposes the owning controller', () {
    testWidgets(
      'removing the Stage from the tree disposes the controller even though '
      'the test double provider registers no onDispose of its own',
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
        addTearDown(() async => transport.dispose());
        final inputs = SongTrainerControllerInputs(
          compilation: const SongPracticeCompilation.playbackOnly(),
          backingAsset: _asset,
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: <Override>[
              ...preferenceOverrides(),
              songTrainerControllerProvider(
                inputs,
              ).overrideWith((ref) => controller),
            ],
            child: MaterialApp(
              theme: SsLightTheme.data(),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: SongTrainerScreen(inputs: inputs),
            ),
          ),
        );
        await tester.pump();
        expect(controller.state.status, SongTrainerStatus.idle);

        // Leave the Stage — as a route pop would.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();

        // `SongTrainerController.dispose()` sets its internal `_disposed`
        // flag SYNCHRONOUSLY, before its first `await` — every subsequent
        // guarded command becomes a no-op. `prepare()` would otherwise move
        // the status to `preparing`/`ready`; the status staying `idle` proves
        // the owning controller was actually notified on this exit path, not
        // merely left for Riverpod's own (here deliberately absent, see the
        // override above) teardown timing.
        await controller.prepare();
        expect(
          controller.state.status,
          SongTrainerStatus.idle,
          reason:
              'The Stage must notify the owning controller\'s dispose/exit '
              'path on every exit — the override above deliberately skips '
              'Riverpod\'s own onDispose so only an explicit presentation-'
              'side notification can make this pass (§0.0/B/B7).',
        );
      },
    );
  });

  group('A3 — 200 percent text scale, en and hu', () {
    for (final locale in <Locale>[const Locale('en'), const Locale('hu')]) {
      testWidgets(
        'setlist session remains overflow-free at 200 percent text scale — '
        '${locale.languageCode} locale',
        (tester) async {
          final setlist = SongSetlist(
            id: 'setlist-scale',
            name: 'Text scale setlist',
            createdAt: DateTime.utc(2026, 8, 4),
            updatedAt: DateTime.utc(2026, 8, 4),
            items: <SongSetlistItem>[
              SongSetlistItem(id: 'a', songId: SongId('song-a')),
            ],
          );

          await tester.pumpWidget(
            _localizedApp(
              MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                child: SetlistSessionScreen(
                  setlist: setlist,
                  mode: SetlistSessionMode.performance,
                  availability: (_) => SetlistItemAvailability.ready,
                  performanceRunner: (item) async =>
                      SetlistItemResult.completed(itemId: item.id),
                ),
              ),
              locale: locale,
            ),
          );
          await tester.pumpAndSettle();

          expect(
            find.byKey(const Key('setlist-session-start')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  });
}

Widget _localizedApp(Widget home, {Locale? locale}) => MaterialApp(
  theme: SsLightTheme.data(),
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: home,
);

final SongAssetReference _asset = SongAssetReference(
  id: SongAssetId('backing'),
  sha256: 'a' * 64,
  extension: 'mp3',
  byteLength: 100,
  mimeType: 'audio/mpeg',
  durationMs: 60000,
);
