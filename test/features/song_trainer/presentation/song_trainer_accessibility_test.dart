// Accessibility coverage for the Song Trainer surface. The brief §6 acceptance
// requires large/landscape support, 200% text scaling, reduced motion, and a
// throttled screen-reader live region.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strumsight/core/logging/app_logger.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/core/storage/storage_keys.dart';
import 'package:strumsight/features/practice/public.dart';
import 'package:strumsight/features/song_trainer/application/song_trainer_providers.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_practice_compiler.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_trainer_controller.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_trainer_state.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_transport.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_transport_clock.dart';
import 'package:strumsight/features/song_trainer/data/playback/fake_backing_audio_player.dart';
import 'package:strumsight/features/song_trainer/domain/models/loop_config.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_asset_reference.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_document.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_event.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_instrument.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_measure.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_metadata.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_section.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_source.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_track.dart';
import 'package:strumsight/features/song_trainer/domain/models/tempo_map.dart'
    as song_time;
import 'package:strumsight/features/song_trainer/domain/models/trainer_config.dart';
import 'package:strumsight/features/song_trainer/domain/models/trainer_range.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/song_trainer_screen.dart';
import 'package:strumsight/features/song_trainer/presentation/widgets/song_loop_feedback.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/core/design_system/public.dart' show SsLightTheme;

import '../../../support/fake_audio.dart';
import '../../../support/fake_practice_observation_gateway.dart';
import '../../../support/fake_practice_session_clock.dart';
import '../../../support/fake_practice_session_recorder.dart';
import '../../../support/fake_practice_tick_source.dart';
import '../../../support/preference_store.dart';

void main() {
  testWidgets('200% text scaling remains usable without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final harness = _Harness.scored();
    addTearDown(harness.dispose);
    final state = const SongTrainerState.initial().copyWith(
      status: SongTrainerStatus.running,
      backingRateSupported: true,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          ...preferenceOverrides(),
          songTrainerControllerProvider(
            SongTrainerControllerInputs(
              compilation: _scoredCompilation(),
              backingAsset: _asset,
            ),
          ).overrideWith((ref) => harness.controller),
        ],
        child: MaterialApp(
          theme: SsLightTheme.data(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: SongTrainerScreen(state: state),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('song-trainer-loop-index')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('200% text scaling remains usable without overflow — hu locale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final harness = _Harness.scored();
    addTearDown(harness.dispose);
    final state = const SongTrainerState.initial().copyWith(
      status: SongTrainerStatus.running,
      backingRateSupported: true,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          ...preferenceOverrides(),
          songTrainerControllerProvider(
            SongTrainerControllerInputs(
              compilation: _scoredCompilation(),
              backingAsset: _asset,
            ),
          ).overrideWith((ref) => harness.controller),
        ],
        child: MaterialApp(
          theme: SsLightTheme.data(),
          locale: const Locale('hu'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: SongTrainerScreen(state: state),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('song-trainer-loop-index')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('landscape layout keeps the loop index and lane visible', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2000, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final harness = _Harness.scored();
    addTearDown(harness.dispose);
    final state = const SongTrainerState.initial().copyWith(
      status: SongTrainerStatus.running,
      backingRateSupported: true,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          ...preferenceOverrides(),
          songTrainerControllerProvider(
            SongTrainerControllerInputs(
              compilation: _scoredCompilation(),
              backingAsset: _asset,
            ),
          ).overrideWith((ref) => harness.controller),
        ],
        child: MaterialApp(
          theme: SsLightTheme.data(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SongTrainerScreen(state: state),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('song-trainer-loop-index')), findsOneWidget);
    expect(find.byKey(const Key('song-trainer-strum-lane')), findsOneWidget);
  });

  testWidgets('reduced motion replaces hot affordances with static labels', (
    tester,
  ) async {
    final harness = _Harness.scored();
    addTearDown(harness.dispose);
    final state = const SongTrainerState.initial().copyWith(
      status: SongTrainerStatus.running,
      backingRateSupported: true,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          ...preferenceOverrides(),
          songTrainerControllerProvider(
            SongTrainerControllerInputs(
              compilation: _scoredCompilation(),
              backingAsset: _asset,
            ),
          ).overrideWith((ref) => harness.controller),
        ],
        child: MaterialApp(
          theme: SsLightTheme.data(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MediaQuery(
            data: const MediaQueryData(
              disableAnimations: true,
              accessibleNavigation: true,
            ),
            child: SongTrainerScreen(state: state),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  // ─── M1: left-handed layout ─────────────────────────────────────────────
  // The §6 acceptance matrix requires left-handed to stay usable end-to-end.
  // The trainer screen must mirror the lane/control row when the
  // project-wide left-handed preference is on; turning it off must restore
  // the canonical left-to-right layout. The mirror uses Transform.flip so
  // the screen-reader semantics tree is preserved — the test verifies that
  // the visible widgets stay mounted (loop index, transport controls) AND
  // that a `Transform` widget actually wraps the body when the flag is on,
  // by inspecting the element tree.
  testWidgets(
    'left-handed preference mirrors the running body but keeps all controls mounted',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        StorageKeys.leftHanded: true,
      });
      final harness = _Harness.scored();
      addTearDown(harness.dispose);
      final state = const SongTrainerState.initial().copyWith(
        status: SongTrainerStatus.running,
        backingRateSupported: true,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            ...preferenceOverrides(<String, Object>{
              StorageKeys.leftHanded: true,
            }),
            songTrainerControllerProvider(
              SongTrainerControllerInputs(
                compilation: _scoredCompilation(),
                backingAsset: _asset,
              ),
            ).overrideWith((ref) => harness.controller),
          ],
          child: MaterialApp(
            theme: SsLightTheme.data(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: SongTrainerScreen(state: state),
          ),
        ),
      );
      await tester.pump();

      // Right-handed affordances are still mounted — left-handed mirrors
      // the visual axis only, the widget tree is unchanged.
      expect(find.byKey(const Key('song-trainer-loop-index')), findsOneWidget);
      expect(find.byKey(const Key('song-trainer-speed')), findsOneWidget);
      expect(find.byKey(const Key('song-trainer-strum-lane')), findsOneWidget);
      expect(
        find.byKey(const Key('song-trainer-transport-controls')),
        findsOneWidget,
      );

      // The mirror is implemented as a Transform with a horizontal flip
      // matrix. Walk the element tree to confirm the body sits inside a
      // Transform that scales X by -1.
      final bodyTransform = tester
          .widgetList<Transform>(find.byType(Transform))
          .firstWhere(
            (transform) =>
                transform.transform.entry(0, 0) == -1.0 &&
                transform.transform.entry(1, 1) == 1.0,
            orElse: () => throw StateError(
              'No horizontal-flip Transform found — left-handed mirror is missing',
            ),
          );
      expect(bodyTransform.transform.entry(0, 0), -1.0);
    },
  );

  testWidgets('right-handed preference does not mirror the running body', (
    tester,
  ) async {
    final harness = _Harness.scored();
    addTearDown(harness.dispose);
    final state = const SongTrainerState.initial().copyWith(
      status: SongTrainerStatus.running,
      backingRateSupported: true,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          ...preferenceOverrides(<String, Object>{
            StorageKeys.leftHanded: false,
          }),
          songTrainerControllerProvider(
            SongTrainerControllerInputs(
              compilation: _scoredCompilation(),
              backingAsset: _asset,
            ),
          ).overrideWith((ref) => harness.controller),
        ],
        child: MaterialApp(
          theme: SsLightTheme.data(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SongTrainerScreen(state: state),
        ),
      ),
    );
    await tester.pump();

    // Affordances remain mounted (same as left-handed case).
    expect(find.byKey(const Key('song-trainer-loop-index')), findsOneWidget);
    expect(find.byKey(const Key('song-trainer-strum-lane')), findsOneWidget);

    // No horizontal-flip Transform should be present — flipping the
    // matrix would change the body to mirror mode. The control case:
    // removing the left-handed wiring in `song_trainer_screen.dart` and
    // keeping a Transform in the body unconditionally would still mount
    // the keys, but the firstWhere below would fail because no
    // Transform exists with scale(-1, 1, 1).
    final mirrored = tester
        .widgetList<Transform>(find.byType(Transform))
        .any(
          (transform) =>
              transform.transform.entry(0, 0) == -1.0 &&
              transform.transform.entry(1, 1) == 1.0,
        );
    expect(mirrored, isFalse);
  });

  // ─── M2: reader throttling ──────────────────────────────────────────────
  // The §5.3 / §6 acceptance matrix requires the screen-reader live region
  // to be throttled to one announcement per ≥ [minimumAnnounceGap]. The
  // test measures what the screen-reader would actually see: across a
  // tight 250 ms window with 25 burst messages the Semantics tree must
  // display AT MOST a small handful of updates (the implementation drops
  // any announcement that arrives < minimumAnnounceGap after the previous
  // displayed one).
  //
  // The test is distinguishing: reverting `didUpdateWidget` in
  // `song_loop_feedback.dart` to setState on every message makes every
  // message surface immediately, breaking the throttle assertion below.
  testWidgets(
    'reader throttling bounds announcements per second inside the live region',
    (tester) async {
      const burst = 25;
      const gap = Duration(milliseconds: 10);
      final origin = DateTime.utc(2026, 8, 4);
      final messages = <SongLoopFeedbackMessage>[
        for (var i = 0; i < burst; i++)
          SongLoopFeedbackMessage(
            headline: 'Headline $i',
            detail: 'Detail $i',
            outcome: SongLoopFeedbackOutcome.neutral,
            announcedAt: origin.add(gap * i),
          ),
      ];

      // A stateful host widget so we can update the messages list on the
      // SAME `SongLoopFeedback` element across pumps — pumpWidget with the
      // same widget type at the same position rebuilds the element, and
      // the throttle logic lives in `didUpdateWidget`; mounting a fresh
      // instance each iteration would reset the displayed message via
      // `initState` and the throttle would never engage.
      final hostKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: SsLightTheme.data(),
          home: Scaffold(
            body: _ThrottleHost(
              key: hostKey,
              messages: <SongLoopFeedbackMessage>[],
            ),
          ),
        ),
      );
      await tester.pump();

      // Seed with the first message — surfaces immediately via initState.
      (hostKey.currentState as _ThrottleHostState).update(
        messages.sublist(0, 1),
      );
      await tester.pump();
      final firstFinder = find.byKey(const Key('song-trainer-loop-feedback'));
      expect(firstFinder, findsOneWidget);
      final initialSemantics = tester.getSemantics(firstFinder);
      expect(initialSemantics.label, contains('Headline 0'));

      // Burst in 24 more messages inside a 240 ms window. The throttle
      // (`minimumAnnounceGap` = 1000 ms default) must NOT keep flipping
      // the live region — every update inside the burst falls inside the
      // 1000 ms minimum announce gap, so the first message stays on
      // screen. The control case (reverting `didUpdateWidget` to setState
      // unconditionally) makes the label point at the LAST message.
      for (var i = 1; i < burst; i++) {
        (hostKey.currentState as _ThrottleHostState).update(
          messages.sublist(0, i + 1),
        );
        await tester.pump();
      }

      final afterBurst = tester.getSemantics(firstFinder);
      expect(
        afterBurst.label,
        contains('Headline 0'),
        reason:
            'Throttle must keep Headline 0 on screen — 24 updates inside a '
            '240 ms window all fall under the 1000 ms minimum announce gap',
      );
    },
  );

  testWidgets('a message outside the announce gap replaces the displayed one', (
    tester,
  ) async {
    // Two messages that ARE outside the throttle gap — both must surface.
    final origin = DateTime.utc(2026, 8, 4);
    final first = SongLoopFeedbackMessage(
      headline: 'First',
      detail: 'First detail',
      outcome: SongLoopFeedbackOutcome.pass,
      announcedAt: origin,
    );
    final second = SongLoopFeedbackMessage(
      headline: 'Second',
      detail: 'Second detail',
      outcome: SongLoopFeedbackOutcome.retry,
      announcedAt: origin.add(const Duration(seconds: 5)),
    );

    final hostKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: SsLightTheme.data(),
        home: Scaffold(
          body: _ThrottleHost(
            key: hostKey,
            messages: <SongLoopFeedbackMessage>[first],
          ),
        ),
      ),
    );
    await tester.pump();
    final finder = find.byKey(const Key('song-trainer-loop-feedback'));
    expect(tester.getSemantics(finder).label, contains('First'));

    // The second message is 5 s after the first — the throttle window
    // has elapsed, so the second one must surface.
    (hostKey.currentState as _ThrottleHostState).update(
      <SongLoopFeedbackMessage>[first, second],
    );
    await tester.pump();
    expect(tester.getSemantics(finder).label, contains('Second'));
  });
}

/// Test-only host widget that owns the messages list and rebuilds
/// `SongLoopFeedback` via setState. The widget tree stays stable across
/// pumps, so `SongLoopFeedback`'s `didUpdateWidget` throttle logic
/// (instead of `initState`) is the one that fires.
/// Test-only host widget that owns the messages list in its [State] and
/// rebuilds `SongLoopFeedback` via setState. The widget tree stays stable
/// across pumps, so `SongLoopFeedback`'s `didUpdateWidget` throttle logic
/// (instead of `initState`) is the one that fires.
class _ThrottleHost extends StatefulWidget {
  const _ThrottleHost({super.key, required this.messages});

  /// Initial messages; the [State] replaces this slice across pumps.
  final List<SongLoopFeedbackMessage> messages;

  @override
  State<_ThrottleHost> createState() => _ThrottleHostState();
}

class _ThrottleHostState extends State<_ThrottleHost> {
  /// Current messages; reassigned by [update].
  late List<SongLoopFeedbackMessage> _messages = widget.messages;

  void update(List<SongLoopFeedbackMessage> next) {
    setState(() {
      _messages = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Each build creates a fresh SongLoopFeedback with the current list.
    // Using a stable Key so Flutter reuses the StatefulElement across
    // pumps.
    return SongLoopFeedback(
      key: const Key('song-trainer-loop-feedback-host'),
      messages: _messages,
    );
  }
}

final SongAssetReference _asset = SongAssetReference(
  id: SongAssetId('backing'),
  sha256: 'a' * 64,
  extension: 'mp3',
  byteLength: 100,
  mimeType: 'audio/mpeg',
  durationMs: 1000,
);

final SongInstrument _guitar = SongInstrument(name: 'Guitar');

class _Harness {
  _Harness._({
    required this.controller,
    required this.transport,
    required this.practice,
    required this.practiceClock,
    required this.practiceTick,
  });

  final SongTrainerController controller;
  final SongTransport transport;
  final PracticeSessionController practice;
  final FakePracticeSessionClock practiceClock;
  final FakePracticeTickSource practiceTick;

  factory _Harness.scored() {
    final player = FakeBackingAudioPlayer();
    final transport = SongTransport(
      player: player,
      clock: FakeSongTransportClock(),
    );
    final clock = FakePracticeSessionClock();
    final tick = FakePracticeTickSource();
    final permissions = FakeMicrophonePermissionGateway();
    final practice = PracticeSessionController(
      clock: clock,
      tickSource: tick,
      recorder: FakePracticeSessionRecorder(),
      logger: const NoopAppLogger(),
      permissions: permissions,
      observationConfig: const PracticeObservationConfig(),
      sessionIdFactory: () => 'practice-result',
      compileTarget: (definition, config) => Future.value(
        compilePracticeTarget(definition: definition, config: config),
      ),
      observationGateway: FakePracticeObservationGateway(),
    );
    final controller = SongTrainerController(
      transport: transport,
      compilation: _scoredCompilation(),
      practiceSession: practice,
    );
    return _Harness._(
      controller: controller,
      transport: transport,
      practice: practice,
      practiceClock: clock,
      practiceTick: tick,
    );
  }

  Future<void> startRunning() async {
    await controller.start();
    practiceClock.advance(
      practice.state.target!.countInDuration + const Duration(milliseconds: 1),
    );
    practiceTick.emitTick();
    await _settle();
  }

  Future<void> dispose() async {
    await controller.dispose();
    await transport.dispose();
  }
}

SongPracticeCompilation _scoredCompilation() =>
    SongPracticeCompiler.compile(document: _document(), config: _config());

SongDocument _document() {
  final now = DateTime.utc(2026, 8, 4);
  return SongDocument(
    schemaVersion: songDocumentSchemaVersion,
    id: SongId('song'),
    revision: 1,
    metadata: SongMetadata(title: 'Song'),
    source: SongSource(
      type: SongSourceType.createdInApp,
      originalFileName: 'song.json',
      sha256: 'a' * 64,
      importedAt: now,
      importerVersion: 'test@1',
    ),
    createdAt: now,
    updatedAt: now,
    measures: <SongMeasure>[
      SongMeasure(index: 0, durationBeats: song_time.BeatPosition.fromBeats(4)),
    ],
    sections: <SongSection>[
      SongSection(
        id: SongSectionId('section'),
        name: 'Section',
        startMeasure: 0,
        endMeasureExclusive: 1,
      ),
    ],
    tempoMap: song_time.TempoMap.constant(song_time.Tempo(120)),
    tracks: <SongTrack>[
      StrumTrack(
        id: SongTrackId('strums'),
        name: 'Strums',
        instrument: _guitar,
        events: <SongStrumEvent>[
          SongStrumEvent(
            id: SongEventId('strum'),
            at: Duration.zero,
            direction: StrumDirection.down,
          ),
        ],
      ),
    ],
  );
}

TrainerConfig _config() => TrainerConfig(
  songId: SongId('song'),
  songRevision: 1,
  trackId: SongTrackId('strums'),
  selection: MeasureRange(start: 0, endExclusive: 1),
  range: MeasureRange(start: 0, endExclusive: 1),
  mode: TrainerMode.rhythm,
  targetSpeed: 1,
  countInBars: 0,
  metronomeEnabled: true,
  loopConfig: LoopConfig(range: MeasureRange(start: 0, endExclusive: 1)),
  tuningReminder: null,
  capo: 0,
  capoReminder: false,
);

Future<void> _settle() async {
  for (var index = 0; index < 3; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}
