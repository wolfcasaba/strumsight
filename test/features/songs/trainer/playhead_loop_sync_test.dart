// A2/A3/A4 — the Song Trainer Stage playhead is driven by the audio clock,
// not a local Timer (ADR 0274 §3). §6.1 mérce-mátrix:
//   - A2: a separate Timer for the playhead must go RED.
//   - A3: rounding the visual loop boundary to the nearest measure must go RED.
//   - A4: resuming from the start of the section (not the exact pause
//     position) must go RED.
// The three mandatory sync-threshold cells (40 ms accepted, 100 ms accepted
// — the bound is inclusive — 180 ms rejected) exercise `PlayheadSync`
// directly, per the ADR 0274 §3 contract.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_trainer_state.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_transport.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_transport_clock.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_transport_command.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_transport_state.dart';
import 'package:strumsight/features/song_trainer/data/playback/fake_backing_audio_player.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_asset_reference.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_event.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/song_trainer_screen.dart';
import 'package:strumsight/features/song_trainer/presentation/widgets/chord_lane.dart';
import 'package:strumsight/features/song_trainer/presentation/widgets/transport_controls.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/core/design_system/public.dart' show SsLightTheme;

import '../../../support/preference_store.dart';

void main() {
  group('PlayheadSync threshold (ADR 0274 §3, bound inclusive at 100 ms)', () {
    test('40 ms delta is in sync', () {
      expect(
        PlayheadSync.isInSync(
          audioPosition: const Duration(milliseconds: 1040),
          visualPosition: const Duration(milliseconds: 1000),
        ),
        isTrue,
      );
    });

    test('exactly 100 ms delta is in sync — the boundary is inclusive', () {
      expect(
        PlayheadSync.isInSync(
          audioPosition: const Duration(milliseconds: 1100),
          visualPosition: const Duration(milliseconds: 1000),
        ),
        isTrue,
      );
    });

    test('180 ms delta is rejected', () {
      expect(
        PlayheadSync.isInSync(
          audioPosition: const Duration(milliseconds: 1180),
          visualPosition: const Duration(milliseconds: 1000),
        ),
        isFalse,
      );
    });
  });

  group('A2 — the lane viewport tracks the audio clock, not a local Timer', () {
    testWidgets(
      'the running lane viewport equals the transport position produced by '
      'a fake audio clock',
      (tester) async {
        final player = FakeBackingAudioPlayer();
        final transport = SongTransport(
          player: player,
          clock: FakeSongTransportClock(),
        );
        addTearDown(transport.dispose);
        await transport.dispatch(PrepareSongTransport(asset: _asset));
        await transport.dispatch(const StartSongTransport());
        (transport.clock as FakeSongTransportClock).advance(
          const Duration(milliseconds: 2500),
        );

        final audioPosition = transport.state.activePosition;
        expect(audioPosition, const Duration(milliseconds: 2500));

        final state = const SongTrainerState.initial().copyWith(
          status: SongTrainerStatus.running,
          transportState: transport.state,
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: preferenceOverrides(),
            child: MaterialApp(
              theme: SsLightTheme.data(),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: SongTrainerScreen(
                state: state,
                chordEvents: <SongChordEvent>[],
              ),
            ),
          ),
        );
        await tester.pump();

        final lane = tester.widget<ChordLane>(find.byType(ChordLane));
        expect(
          PlayheadSync.isInSync(
            audioPosition: audioPosition,
            visualPosition: lane.viewportStart,
          ),
          isTrue,
        );
        expect(lane.viewportStart, audioPosition);
      },
    );

    testWidgets(
      'the viewport never drifts on its own — pumping ten seconds of frame '
      'time without a state change leaves it exactly where it was',
      (tester) async {
        final state = const SongTrainerState.initial().copyWith(
          status: SongTrainerStatus.running,
          transportState: const SongTransportState(
            phase: SongTransportPhase.playing,
            activePosition: Duration(milliseconds: 1234),
          ),
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: preferenceOverrides(),
            child: MaterialApp(
              theme: SsLightTheme.data(),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: SongTrainerScreen(
                state: state,
                chordEvents: <SongChordEvent>[],
              ),
            ),
          ),
        );
        await tester.pump();
        final before = tester
            .widget<ChordLane>(find.byType(ChordLane))
            .viewportStart;

        // A control-case Timer-driven playhead would have advanced by ~10 s
        // of frame time here even though the supplied state never changed.
        await tester.pump(const Duration(seconds: 10));

        final after = tester
            .widget<ChordLane>(find.byType(ChordLane))
            .viewportStart;
        expect(after, before);
        expect(before, const Duration(milliseconds: 1234));
      },
    );
  });

  group('A3 — the visual loop boundary matches the audible one exactly', () {
    testWidgets(
      'the viewport end clamps to the exact loop range end, not a rounded '
      'measure boundary',
      (tester) async {
        const loopRangeEnd = Duration(milliseconds: 3333);
        final state = const SongTrainerState.initial().copyWith(
          status: SongTrainerStatus.running,
          transportState: const SongTransportState(
            phase: SongTransportPhase.playing,
            activePosition: Duration(milliseconds: 1000),
          ),
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: preferenceOverrides(),
            child: MaterialApp(
              theme: SsLightTheme.data(),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: SongTrainerScreen(
                state: state,
                chordEvents: <SongChordEvent>[],
                loopRangeEnd: loopRangeEnd,
              ),
            ),
          ),
        );
        await tester.pump();

        final lane = tester.widget<ChordLane>(find.byType(ChordLane));
        // A viewport span of 4 s from 1000 ms would normally end at 5000 ms —
        // the loop boundary at 3333 ms must clamp it EXACTLY, not to the
        // nearest second or measure.
        expect(lane.viewportEnd, loopRangeEnd);
      },
    );

    testWidgets(
      'a loop range end past the natural viewport span has no effect',
      (tester) async {
        final state = const SongTrainerState.initial().copyWith(
          status: SongTrainerStatus.running,
          transportState: const SongTransportState(
            phase: SongTransportPhase.playing,
            activePosition: Duration.zero,
          ),
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: preferenceOverrides(),
            child: MaterialApp(
              theme: SsLightTheme.data(),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: SongTrainerScreen(
                state: state,
                chordEvents: <SongChordEvent>[],
                loopRangeEnd: const Duration(minutes: 10),
              ),
            ),
          ),
        );
        await tester.pump();

        final lane = tester.widget<ChordLane>(find.byType(ChordLane));
        expect(lane.viewportEnd, const Duration(seconds: 4));
      },
    );
  });

  group('A4 — pausing surfaces the exact resume position', () {
    testWidgets(
      'the paused position label carries the exact millisecond value, not a '
      'value rounded to whole seconds or reset to the section start',
      (tester) async {
        final state = const SongTrainerState.initial().copyWith(
          status: SongTrainerStatus.paused,
          backingRateSupported: false,
          transportState: const SongTransportState(
            phase: SongTransportPhase.paused,
            activePosition: Duration(milliseconds: 12345),
          ),
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: preferenceOverrides(),
            child: MaterialApp(
              theme: SsLightTheme.data(),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: SongTrainerScreen(state: state),
            ),
          ),
        );
        await tester.pump();

        final finder = find.byKey(const Key('song-trainer-paused-position'));
        expect(finder, findsOneWidget);
        final semantics = tester.getSemantics(finder);
        // 12345 ms == 0:12.345 — the control case (resume-from-section-start)
        // would show 0:00.000, and a whole-second rounding would show 0:12.000.
        expect(semantics.label, contains('12.345'));
        expect(semantics.label, isNot(contains('0:00')));
      },
    );
  });
}

final SongAssetReference _asset = SongAssetReference(
  id: SongAssetId('backing'),
  sha256: 'a' * 64,
  extension: 'mp3',
  byteLength: 100,
  mimeType: 'audio/mpeg',
  durationMs: 60000,
);
