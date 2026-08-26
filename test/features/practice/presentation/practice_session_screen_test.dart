// E02-R13 §6 A1, A1b, A2, A3, A4, A5 — practice session screen.
//
// The screen is a thin shell over a presentation-side boundary
// (PracticeSessionHost); the test fakes the host with controllable
// StreamControllers and a call-recording `send` so every cell of the
// matrix in the brief is asserted on a real rendered widget.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/platform/platform_providers.dart';
import 'package:strumsight/core/widgets/mic_permission_banner.dart';
import 'package:strumsight/features/practice/application/practice_session_command.dart';
import 'package:strumsight/features/practice/application/practice_session_effect.dart';
import 'package:strumsight/features/practice/domain/model/beat_position.dart';
import 'package:strumsight/features/practice/domain/model/meter.dart';
import 'package:strumsight/features/practice/domain/model/practice_definition.dart';
import 'package:strumsight/features/practice/domain/model/practice_event.dart';
import 'package:strumsight/features/practice/domain/model/practice_mode.dart';
import 'package:strumsight/features/practice/domain/model/practice_session_config.dart';
import 'package:strumsight/features/practice/domain/model/practice_session_state.dart';
import 'package:strumsight/features/practice/domain/model/practice_source.dart';
import 'package:strumsight/features/practice/domain/model/scoring_profile.dart';
import 'package:strumsight/features/practice/domain/model/tempo.dart';
import 'package:strumsight/features/practice/presentation/practice_effect_listener.dart';
import 'package:strumsight/features/practice/presentation/screens/practice_session_screen.dart';
import 'package:strumsight/features/practice/presentation/widgets/practice_controls.dart';
import 'package:strumsight/features/practice/presentation/widgets/practice_error_panel.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/l10n/app_localizations_en.dart';

import '../../../support/fake_audio.dart';

/// Inline English localizations so the test asserts on the exact
/// rendered string without having to `await tester.pumpAndSettle()`
/// the locale-loading async pipeline.
AppLocalizations l10nEn() => AppLocalizationsEn();

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

/// Fake [PracticeSessionHost] with controllable streams and a call-recording
/// `send`. Tests verify both the rendered widget tree and the command
/// stream — neither is trusted on its own.
class _FakeSessionHost implements PracticeSessionHost {
  final StreamController<PracticeSessionState> _statesController =
      StreamController<PracticeSessionState>.broadcast();
  final StreamController<PracticeSessionEffect> _effectsController =
      StreamController<PracticeSessionEffect>.broadcast();

  final List<PracticeSessionCommand> sent = <PracticeSessionCommand>[];
  int? liveScore;
  PracticeSessionState _state = PracticeSessionState.initial;

  @override
  Stream<PracticeSessionState> get states => _statesController.stream;

  @override
  PracticeSessionState get state => _state;

  @override
  Stream<PracticeSessionEffect> get effects => _effectsController.stream;

  @override
  int? get liveOverallPerMille => liveScore;

  @override
  void send(PracticeSessionCommand command) {
    sent.add(command);
  }

  void emitState(PracticeSessionState state) {
    _state = state;
    _statesController.add(state);
  }

  void emitEffect(PracticeSessionEffect effect) {
    _effectsController.add(effect);
  }

  Future<void> close() async {
    await _statesController.close();
    await _effectsController.close();
  }
}

class _RecordingFeedback implements PracticeFeedbackOutput {
  int hapticCalls = 0;
  final List<int> countInClicks = <int>[];
  final List<String> announcements = <String>[];
  int openSettingsCalls = 0;

  @override
  void haptic() => hapticCalls++;
  @override
  void countInClick(int beatIndex) => countInClicks.add(beatIndex);
  @override
  void announce(String message) => announcements.add(message);
  @override
  void openPermissionSettings() => openSettingsCalls++;
}

class _RecordingNavigationSink {
  int calls = 0;
  void call() => calls++;
}

PracticeDefinition _fixtureDefinition() => PracticeDefinition(
  id: 'fixture.session',
  schemaVersion: 1,
  titleKey: 'practiceCatalogTestSetupTitle',
  descriptionKey: 'practiceCatalogTestSetupDescription',
  mode: PracticeMode.strumPattern,
  source: PracticeSource.builtin,
  meter: const Meter(beatsPerBar: 4),
  defaultTempo: const Tempo(100),
  totalBeats: BeatPosition.quarters(16),
  events: const <PracticeEvent>[],
  scoringProfile: ScoringProfile.legacyLearnParity,
  skillTags: const ['test'],
  displayTitle: 'Session fixture',
);

PracticeSessionConfig _fixtureConfig() => PracticeSessionConfig(
  definitionId: 'fixture.session',
  definitionSnapshotVersion: 1,
  effectiveTempo: const Tempo(100),
  countInBars: 1,
  loopCount: 1,
  metronomeEnabled: false,
  accentEnabled: false,
  backingEnabled: false,
  scoringProfileId: 'chordProgressionDefault',
  inputLatency: Duration.zero,
  visualLatency: Duration.zero,
  expectedChordHintEnabled: true,
  sessionTimeout: const Duration(minutes: 10),
  reducedMotion: false,
);

PracticeSessionState _stateFor(
  PracticeSessionStatus status, {
  PracticeDefinition? definition,
  PracticeSessionConfig? config,
  int attemptIndex = 0,
  int countInSpanBeats = 0,
  int emittedCountInClicks = 0,
  Duration activeElapsed = Duration.zero,
}) => PracticeSessionState(
  status: status,
  definition: definition,
  config: config,
  attemptIndex: attemptIndex,
  countInSpanBeats: countInSpanBeats,
  emittedCountInClicks: emittedCountInClicks,
  activeElapsed: activeElapsed,
);

Future<void> _pumpScreen(
  WidgetTester tester, {
  _FakeSessionHost? host,
  _RecordingFeedback? feedback,
  _RecordingNavigationSink? navSink,
  bool hapticsOn = true,
  FakeAppLifecycleEvents? lifecycle,
}) async {
  final fb = feedback ?? _RecordingFeedback();
  final nav = navSink ?? _RecordingNavigationSink();
  final lc = lifecycle ?? FakeAppLifecycleEvents();
  // The screen now renders through `SsStageScaffold`, which picks its
  // compact (portrait phone) vs wide (landscape/tablet) layout from the
  // viewport (ADR 0276). `flutter_test`'s default 800×600 surface reads as
  // landscape and would silently exercise the two-column `_WideStage`
  // instead of the phone layout every real user sees — pin a compact
  // portrait phone size, same convention as
  // `test/features/tuner/tuner_ui_mapping_test.dart`.
  tester.view.physicalSize = const Size(412, 915);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (host != null) practiceSessionHostProvider.overrideWithValue(host),
        practiceFeedbackOutputProvider.overrideWithValue(fb),
        practiceResultNavigationSinkProvider.overrideWithValue(nav.call),
        practiceHapticsEnabledProvider.overrideWithValue(hapticsOn),
        appLifecycleEventsProvider.overrideWithValue(lc),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: PracticeSessionScreen(),
      ),
    ),
  );
  await tester.pump();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // -----------------------------------------------------------------
  // A1 — 8 visible statuses
  // -----------------------------------------------------------------
  group('A1 — status render matrix', () {
    testWidgets('preparing shows the progress indicator', (tester) async {
      final host = _FakeSessionHost();
      addTearDown(host.close);
      host.emitState(_stateFor(PracticeSessionStatus.preparing));
      await _pumpScreen(tester, host: host);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(
        find.text(l10nEn().practiceSessionStatusPreparing),
        findsOneWidget,
      );
    });

    testWidgets('permissionRequired shows the CORE MicPermissionBanner', (
      tester,
    ) async {
      final def = _fixtureDefinition();
      final cfg = _fixtureConfig();
      final host = _FakeSessionHost();
      addTearDown(host.close);
      host.emitState(
        _stateFor(
          PracticeSessionStatus.permissionRequired,
          definition: def,
          config: cfg,
        ),
      );
      await _pumpScreen(tester, host: host);
      // Core widget, not the local card.
      expect(find.byType(MicPermissionBanner), findsOneWidget);
      expect(find.text(l10nEn().micPermissionBody), findsOneWidget);
      // The prepare button issues a PreparePractice command (NOT
      // GrantPermission — ADR 0079 §7).
      await tester.tap(find.text(l10nEn().practiceSessionPrepare));
      await tester.pump();
      expect(host.sent.length, 1);
      expect(host.sent.single, isA<PreparePractice>());
    });

    testWidgets('ready shows Start, no count-in overlay', (tester) async {
      final host = _FakeSessionHost();
      addTearDown(host.close);
      host.emitState(_stateFor(PracticeSessionStatus.ready));
      await _pumpScreen(tester, host: host);
      expect(find.text(l10nEn().practiceSessionStart), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(
        find.textContaining(l10nEn().practiceSessionCountIn),
        findsNothing,
      );
    });

    testWidgets('countIn shows the remaining beats overlay', (tester) async {
      final host = _FakeSessionHost();
      addTearDown(host.close);
      host.emitState(
        _stateFor(
          PracticeSessionStatus.countIn,
          countInSpanBeats: 4,
          emittedCountInClicks: 1,
        ),
      );
      await _pumpScreen(tester, host: host);
      // 4 span - 1 emitted = 3 remaining.
      expect(find.textContaining('3'), findsWidgets);
      // The label "Count-in beats remaining" is rendered with the count.
      expect(
        find.textContaining(l10nEn().practiceSessionCountIn),
        findsOneWidget,
      );
    });

    testWidgets('running shows HUD with elapsed/attempt/score', (tester) async {
      final host = _FakeSessionHost();
      host.liveScore = 870;
      addTearDown(host.close);
      host.emitState(
        _stateFor(
          PracticeSessionStatus.running,
          attemptIndex: 2,
          activeElapsed: const Duration(minutes: 1, seconds: 23),
        ),
      );
      await _pumpScreen(tester, host: host);
      expect(find.text(l10nEn().practiceSessionStatusLabel), findsOneWidget);
      expect(find.text(l10nEn().practiceSessionStatusRunning), findsOneWidget);
      expect(
        find.textContaining(l10nEn().practiceSessionAttempt),
        findsOneWidget,
      );
      // attemptIndex + 1 (zero-based -> 3) shown in the HUD.
      expect(find.textContaining('3'), findsWidgets);
      // 87.0% — live score rendered.
      expect(find.textContaining('87.0%'), findsOneWidget);
      // Pause available.
      expect(find.text(l10nEn().practiceSessionPause), findsOneWidget);
    });

    testWidgets('paused shows the pause label and Resume', (tester) async {
      final host = _FakeSessionHost();
      addTearDown(host.close);
      host.emitState(_stateFor(PracticeSessionStatus.paused));
      await _pumpScreen(tester, host: host);
      expect(find.text(l10nEn().practiceSessionStatusPaused), findsOneWidget);
      // Two Resume affordances now coexist by design (SDD UI-20): the
      // bottom transport's own Resume, and the Pause/Recovery overlay's
      // (§0.0/R8) — both send the identical `ResumePractice` command.
      expect(find.text(l10nEn().practiceSessionResume), findsWidgets);
      expect(
        find.byKey(const ValueKey('practice-pause-overlay')),
        findsOneWidget,
      );
    });

    testWidgets('finishing shows progress AND disables the Exit button', (
      tester,
    ) async {
      final host = _FakeSessionHost();
      addTearDown(host.close);
      host.emitState(_stateFor(PracticeSessionStatus.finishing));
      await _pumpScreen(tester, host: host);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      // Exit button is rendered but disabled.
      final exitButton = tester.widget<ElevatedButton>(
        find
            .ancestor(
              of: find.text(l10nEn().practiceSessionExit),
              matching: find.byType(ElevatedButton),
            )
            .first,
      );
      expect(exitButton.onPressed, isNull, reason: 'M4: finishing freezes UI');
    });

    testWidgets('failed renders the in-screen error panel with Retry', (
      tester,
    ) async {
      final def = _fixtureDefinition();
      final cfg = _fixtureConfig();
      final host = _FakeSessionHost();
      addTearDown(host.close);
      host.emitState(
        _stateFor(
          PracticeSessionStatus.failed,
          definition: def,
          config: cfg,
        ).copyWith(
          recoverableFailure: const UnknownFailure(
            code: 'practice.target_uncompilable',
          ),
        ),
      );
      await _pumpScreen(tester, host: host);
      // Panel + retry button + localised body text — NOT raw failure code.
      expect(find.text(l10nEn().practiceSessionErrorTitle), findsWidgets);
      expect(find.text(l10nEn().practiceSessionErrorBody), findsWidgets);
      expect(find.text(l10nEn().practiceSessionRetry), findsOneWidget);
      expect(find.textContaining('practice.target_uncompilable'), findsNothing);
    });
  });

  // -----------------------------------------------------------------
  // A1b — remaining statuses + null host
  // -----------------------------------------------------------------
  group('A1b — remaining three statuses + null host', () {
    testWidgets('idle renders the neutral state message', (tester) async {
      final host = _FakeSessionHost();
      addTearDown(host.close);
      host.emitState(_stateFor(PracticeSessionStatus.idle));
      await _pumpScreen(tester, host: host);
      // The PracticeStateMessage widget renders the local "state: name"
      // form so the screen never leaks a raw enum name.
      expect(
        find.textContaining(l10nEn().practiceSessionStateMessage('idle')),
        findsOneWidget,
      );
      // No exception, no command emitted.
      expect(host.sent, isEmpty);
    });

    testWidgets('completed renders the complete state + an exit path', (
      tester,
    ) async {
      final host = _FakeSessionHost();
      addTearDown(host.close);
      host.emitState(_stateFor(PracticeSessionStatus.completed));
      await _pumpScreen(tester, host: host);
      expect(
        find.textContaining(l10nEn().practiceSessionStateMessage('completed')),
        findsOneWidget,
      );
      // Exit is available so the user can leave the screen.
      expect(find.text(l10nEn().practiceSessionExit), findsOneWidget);
    });

    testWidgets('cancelled renders the cancelled state + exit path', (
      tester,
    ) async {
      final host = _FakeSessionHost();
      addTearDown(host.close);
      host.emitState(_stateFor(PracticeSessionStatus.cancelled));
      await _pumpScreen(tester, host: host);
      expect(
        find.textContaining(l10nEn().practiceSessionStateMessage('cancelled')),
        findsOneWidget,
      );
      expect(find.text(l10nEn().practiceSessionExit), findsOneWidget);
    });

    testWidgets('null host renders the unavailable state — no exception', (
      tester,
    ) async {
      // No host is registered; the production default of
      // `practiceSessionHostProvider` is `null`, and the screen must
      // short-circuit to the unavailable EmptyState (ADR 0079 §2).
      final lc = FakeAppLifecycleEvents();
      final fb = _RecordingFeedback();
      final nav = _RecordingNavigationSink();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            practiceFeedbackOutputProvider.overrideWithValue(fb),
            practiceResultNavigationSinkProvider.overrideWithValue(nav.call),
            practiceHapticsEnabledProvider.overrideWithValue(true),
            appLifecycleEventsProvider.overrideWithValue(lc),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: PracticeSessionScreen(),
          ),
        ),
      );
      await tester.pump();
      expect(
        find.text(l10nEn().practiceSessionUnavailableTitle),
        findsOneWidget,
      );
      expect(
        find.text(l10nEn().practiceSessionUnavailableBody),
        findsOneWidget,
      );
      // No command was sent (the test would crash before getting here if
      // the screen had thrown while the host was null).
      expect(fb.hapticCalls, 0);
    });
  });

  // -----------------------------------------------------------------
  // A2 — no business-logic symbols in the presentation
  // -----------------------------------------------------------------
  group('A2 — no business-logic symbols in the new presentation files', () {
    final files = <File>[
      File(
        'lib/features/practice/presentation/screens/practice_session_screen.dart',
      ),
      File('lib/features/practice/presentation/widgets/practice_hud.dart'),
      File('lib/features/practice/presentation/widgets/practice_controls.dart'),
      File(
        'lib/features/practice/presentation/widgets/practice_count_in_overlay.dart',
      ),
      File(
        'lib/features/practice/presentation/widgets/practice_error_panel.dart',
      ),
      File('lib/features/practice/presentation/practice_effect_listener.dart'),
    ];

    test('all six files exist on disk', () {
      for (final f in files) {
        expect(f.existsSync(), isTrue, reason: '${f.path} must exist');
      }
    });

    test('no Ticker / Stopwatch / DateTime.now( / LessonScorer / StrumEngine / '
        'Metronome( in the new presentation files', () {
      const banned = <String>[
        'Ticker',
        'Stopwatch',
        'DateTime.now(',
        'LessonScorer',
        'StrumEngine',
        'Metronome(',
      ];
      for (final f in files) {
        final src = _stripComments(f.readAsStringSync());
        for (final needle in banned) {
          expect(
            _occurrences(src, needle),
            0,
            reason: '${f.path} must not contain $needle',
          );
        }
      }
    });

    test('no `domain/service/` import in the new presentation files', () {
      for (final f in files) {
        final src = _stripComments(f.readAsStringSync());
        expect(
          _occurrences(src, 'domain/service/'),
          0,
          reason: '${f.path} imports a service',
        );
      }
    });

    test('no flutter_riverpod legacy import remains under lib', () {
      final dartFiles = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'));
      for (final file in dartFiles) {
        expect(
          file.readAsStringSync(),
          isNot(contains('package:flutter_riverpod/legacy.dart')),
          reason: '${file.path} imports the legacy Riverpod API',
        );
      }
    });
  });

  // -----------------------------------------------------------------
  // A3 — the effect fires exactly once
  // -----------------------------------------------------------------
  group('A3 — effect single-fire matrix', () {
    testWidgets('one PlayHaptic + three rebuilds → 1 haptic call', (
      tester,
    ) async {
      final host = _FakeSessionHost();
      final fb = _RecordingFeedback();
      addTearDown(host.close);
      host.emitState(_stateFor(PracticeSessionStatus.running));
      await _pumpScreen(tester, host: host, feedback: fb);
      host.emitEffect(const PlayHaptic());
      // Three rebuilds via re-emit of the same state.
      for (var i = 0; i < 3; i++) {
        host.emitState(_stateFor(PracticeSessionStatus.running));
        await tester.pump();
      }
      // Drain microtasks to be sure the effect handler ran.
      await tester.pump(const Duration(milliseconds: 10));
      expect(fb.hapticCalls, 1);
    });

    testWidgets('one NavigateToResult + three rebuilds → 1 navigation call', (
      tester,
    ) async {
      final host = _FakeSessionHost();
      final nav = _RecordingNavigationSink();
      addTearDown(host.close);
      host.emitState(_stateFor(PracticeSessionStatus.running));
      await _pumpScreen(tester, host: host, navSink: nav);
      host.emitEffect(const NavigateToResult());
      for (var i = 0; i < 3; i++) {
        host.emitState(_stateFor(PracticeSessionStatus.running));
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 10));
      expect(nav.calls, 1);
    });

    testWidgets('two distinct PlayCountInClick → 2 count-in click calls', (
      tester,
    ) async {
      final host = _FakeSessionHost();
      final fb = _RecordingFeedback();
      addTearDown(host.close);
      host.emitState(_stateFor(PracticeSessionStatus.countIn));
      await _pumpScreen(tester, host: host, feedback: fb);
      host.emitEffect(const PlayCountInClick(0));
      host.emitEffect(const PlayCountInClick(1));
      await tester.pump(const Duration(milliseconds: 10));
      expect(fb.countInClicks, [0, 1]);
    });

    testWidgets('one ShowPermissionSettings → 1 openPermissionSettings call', (
      tester,
    ) async {
      final host = _FakeSessionHost();
      final fb = _RecordingFeedback();
      addTearDown(host.close);
      host.emitState(_stateFor(PracticeSessionStatus.permissionRequired));
      await _pumpScreen(tester, host: host, feedback: fb);
      host.emitEffect(const ShowPermissionSettings());
      await tester.pump(const Duration(milliseconds: 10));
      expect(fb.openSettingsCalls, 1);
    });

    testWidgets(
      'AnnounceAccessibilityFeedback("anything") → 0 calls, no throw',
      (tester) async {
        final host = _FakeSessionHost();
        final fb = _RecordingFeedback();
        final nav = _RecordingNavigationSink();
        addTearDown(host.close);
        host.emitState(_stateFor(PracticeSessionStatus.running));
        await _pumpScreen(tester, host: host, feedback: fb, navSink: nav);
        host.emitEffect(const AnnounceAccessibilityFeedback('aria.key'));
        await tester.pump(const Duration(milliseconds: 10));
        expect(fb.announcements, isEmpty);
        expect(fb.hapticCalls, 0);
        expect(nav.calls, 0);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('haptics disabled + PlayHaptic → 0 haptic calls', (
      tester,
    ) async {
      final host = _FakeSessionHost();
      final fb = _RecordingFeedback();
      addTearDown(host.close);
      host.emitState(_stateFor(PracticeSessionStatus.running));
      await _pumpScreen(tester, host: host, feedback: fb, hapticsOn: false);
      host.emitEffect(const PlayHaptic());
      await tester.pump(const Duration(milliseconds: 10));
      expect(fb.hapticCalls, 0);
    });
  });

  group('Review regressions — recoverable errors', () {
    testWidgets(
      'failed + ShowRecoverableError renders one panel and one error title',
      (tester) async {
        const failure = UnknownFailure(code: 'practice.target_uncompilable');
        final host = _FakeSessionHost();
        addTearDown(host.close);
        host.emitState(
          _stateFor(
            PracticeSessionStatus.failed,
            definition: _fixtureDefinition(),
            config: _fixtureConfig(),
          ).copyWith(recoverableFailure: failure),
        );
        await _pumpScreen(tester, host: host);

        host.emitEffect(const ShowRecoverableError(failure));
        await tester.pump(const Duration(milliseconds: 10));

        expect(find.byType(PracticeErrorPanel), findsOneWidget);
        expect(find.text(l10nEn().practiceSessionErrorTitle), findsOneWidget);
      },
    );

    testWidgets(
      'leave and re-enter in the same ProviderScope shows no stale error',
      (tester) async {
        final host = _FakeSessionHost();
        final feedback = _RecordingFeedback();
        final navigation = _RecordingNavigationSink();
        final lifecycle = FakeAppLifecycleEvents();
        final sessionVisible = ValueNotifier<bool>(true);
        addTearDown(host.close);
        addTearDown(sessionVisible.dispose);
        host.emitState(_stateFor(PracticeSessionStatus.running));

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              practiceSessionHostProvider.overrideWithValue(host),
              practiceFeedbackOutputProvider.overrideWithValue(feedback),
              practiceResultNavigationSinkProvider.overrideWithValue(
                navigation.call,
              ),
              practiceHapticsEnabledProvider.overrideWithValue(true),
              appLifecycleEventsProvider.overrideWithValue(lifecycle),
            ],
            child: ValueListenableBuilder<bool>(
              valueListenable: sessionVisible,
              builder: (context, visible, child) => MaterialApp(
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: visible
                    ? const PracticeSessionScreen()
                    : const SizedBox.shrink(),
              ),
            ),
          ),
        );
        await tester.pump();
        host.emitEffect(
          const ShowRecoverableError(
            UnknownFailure(code: 'practice.target_uncompilable'),
          ),
        );
        await tester.pump(const Duration(milliseconds: 10));
        expect(find.text(l10nEn().practiceSessionErrorTitle), findsOneWidget);

        sessionVisible.value = false;
        await tester.pump();
        sessionVisible.value = true;
        await tester.pump();

        expect(find.byType(PracticeErrorPanel), findsNothing);
        expect(find.text(l10nEn().practiceSessionErrorTitle), findsNothing);
      },
    );
  });

  // -----------------------------------------------------------------
  // A4 — exit matrix: command per (from-status × action)
  // -----------------------------------------------------------------
  group('A4 — exit matrix', () {
    Future<void> driveExit(
      WidgetTester tester,
      _FakeSessionHost host, {
      required PracticeSessionStatus status,
      required Future<void> Function() act,
    }) async {
      host.emitState(_stateFor(status));
      await _pumpScreen(tester, host: host);
      await act();
      // Drain the async chain (showDialog pop → CancelPractice send →
      // Navigator.pop). A continuous indicator (preparing/finishing)
      // would make `pumpAndSettle` time out, so we pump in bounded
      // slices and verify the expected state.
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    testWidgets('preparing: no confirmation, 0 commands, screen stays', (
      tester,
    ) async {
      final host = _FakeSessionHost();
      addTearDown(host.close);
      await driveExit(
        tester,
        host,
        status: PracticeSessionStatus.preparing,
        act: () async {
          await tester.tap(find.text(l10nEn().practiceSessionExit));
        },
      );
      expect(host.sent, isEmpty);
      expect(
        find.text(l10nEn().practiceSessionTitle),
        findsOneWidget,
        reason: 'preparing exit is a no-op',
      );
    });

    testWidgets('ready: confirmation skipped, 1 CancelPractice', (
      tester,
    ) async {
      final host = _FakeSessionHost();
      addTearDown(host.close);
      await driveExit(
        tester,
        host,
        status: PracticeSessionStatus.ready,
        act: () async {
          await tester.tap(find.text(l10nEn().practiceSessionExit));
        },
      );
      expect(host.sent.length, 1);
      expect(host.sent.single, isA<CancelPractice>());
    });

    testWidgets('countIn: confirmation shown, confirmed → 1 CancelPractice', (
      tester,
    ) async {
      final host = _FakeSessionHost();
      addTearDown(host.close);
      await driveExit(
        tester,
        host,
        status: PracticeSessionStatus.countIn,
        act: () async {
          // First, tap the Exit button in the controls row. There may
          // also be "Exit" text widgets rendered later (the dialog);
          // use the controls' button directly via ElevatedButton.
          await tester.tap(
            find.widgetWithText(ElevatedButton, l10nEn().practiceSessionExit),
          );
          // Pump the dialog route in. The transition is a fadeIn +
          // scale, so multiple bounded pumps are needed.
          for (var i = 0; i < 6; i++) {
            await tester.pump(const Duration(milliseconds: 50));
          }
          // Confirm the dialog by tapping the ElevatedButton labelled
          // "Exit" inside the dialog (the action button — the title
          // is a Text, not a button).
          final confirmButton = find
              .descendant(
                of: find.byType(AlertDialog),
                matching: find.widgetWithText(
                  ElevatedButton,
                  l10nEn().practiceSessionExit,
                ),
              )
              .first;
          await tester.tap(confirmButton);
          // Drain the Navigator.pop → send CancelPractice → pop route.
          for (var i = 0; i < 6; i++) {
            await tester.pump(const Duration(milliseconds: 50));
          }
        },
      );
      expect(host.sent.length, 1);
      expect(host.sent.single, isA<CancelPractice>());
    });

    testWidgets('running: confirmation shown, confirmed → 1 CancelPractice', (
      tester,
    ) async {
      final host = _FakeSessionHost();
      addTearDown(host.close);
      await driveExit(
        tester,
        host,
        status: PracticeSessionStatus.running,
        act: () async {
          await tester.tap(
            find.widgetWithText(ElevatedButton, l10nEn().practiceSessionExit),
          );
          for (var i = 0; i < 6; i++) {
            await tester.pump(const Duration(milliseconds: 50));
          }
          final confirmButton = find
              .descendant(
                of: find.byType(AlertDialog),
                matching: find.widgetWithText(
                  ElevatedButton,
                  l10nEn().practiceSessionExit,
                ),
              )
              .first;
          await tester.tap(confirmButton);
          for (var i = 0; i < 6; i++) {
            await tester.pump(const Duration(milliseconds: 50));
          }
        },
      );
      expect(host.sent.length, 1);
      expect(host.sent.single, isA<CancelPractice>());
    });

    testWidgets('paused: confirmation shown, confirmed → 1 CancelPractice', (
      tester,
    ) async {
      final host = _FakeSessionHost();
      addTearDown(host.close);
      await driveExit(
        tester,
        host,
        status: PracticeSessionStatus.paused,
        act: () async {
          await tester.tap(
            find.widgetWithText(ElevatedButton, l10nEn().practiceSessionExit),
          );
          for (var i = 0; i < 6; i++) {
            await tester.pump(const Duration(milliseconds: 50));
          }
          final confirmButton = find
              .descendant(
                of: find.byType(AlertDialog),
                matching: find.widgetWithText(
                  ElevatedButton,
                  l10nEn().practiceSessionExit,
                ),
              )
              .first;
          await tester.tap(confirmButton);
          for (var i = 0; i < 6; i++) {
            await tester.pump(const Duration(milliseconds: 50));
          }
        },
      );
      expect(host.sent.length, 1);
      expect(host.sent.single, isA<CancelPractice>());
    });

    testWidgets('countIn: confirmation rejected → 0 commands, screen stays', (
      tester,
    ) async {
      final host = _FakeSessionHost();
      addTearDown(host.close);
      await driveExit(
        tester,
        host,
        status: PracticeSessionStatus.countIn,
        act: () async {
          await tester.tap(
            find.widgetWithText(ElevatedButton, l10nEn().practiceSessionExit),
          );
          for (var i = 0; i < 6; i++) {
            await tester.pump(const Duration(milliseconds: 50));
          }
          // Tap "Stay" to reject the confirmation.
          await tester.tap(
            find.widgetWithText(TextButton, l10nEn().practiceSessionStay),
          );
          for (var i = 0; i < 6; i++) {
            await tester.pump(const Duration(milliseconds: 50));
          }
        },
      );
      expect(host.sent, isEmpty);
      expect(
        find.text(l10nEn().practiceSessionTitle),
        findsOneWidget,
        reason: 'rejected exit does not navigate away',
      );
    });

    testWidgets('finishing: no exit possible, 0 commands', (tester) async {
      final host = _FakeSessionHost();
      addTearDown(host.close);
      host.emitState(_stateFor(PracticeSessionStatus.finishing));
      await _pumpScreen(tester, host: host);
      // The button itself is disabled — `onPressed: null`. Trying to tap
      // it should not produce any command.
      await tester.tap(
        find.text(l10nEn().practiceSessionExit),
        warnIfMissed: false,
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(host.sent, isEmpty);
    });

    testWidgets('completed: no confirmation, 0 commands', (tester) async {
      final host = _FakeSessionHost();
      addTearDown(host.close);
      host.emitState(_stateFor(PracticeSessionStatus.completed));
      await _pumpScreen(tester, host: host);
      await tester.tap(find.text(l10nEn().practiceSessionExit));
      await tester.pump(const Duration(milliseconds: 300));
      expect(host.sent, isEmpty);
    });

    testWidgets('cancelled: no confirmation, 0 commands', (tester) async {
      final host = _FakeSessionHost();
      addTearDown(host.close);
      host.emitState(_stateFor(PracticeSessionStatus.cancelled));
      await _pumpScreen(tester, host: host);
      await tester.tap(find.text(l10nEn().practiceSessionExit));
      await tester.pump(const Duration(milliseconds: 300));
      expect(host.sent, isEmpty);
    });

    testWidgets('failed: no confirmation, 0 commands', (tester) async {
      final host = _FakeSessionHost();
      addTearDown(host.close);
      host.emitState(_stateFor(PracticeSessionStatus.failed));
      await _pumpScreen(tester, host: host);
      await tester.tap(find.text(l10nEn().practiceSessionExit));
      await tester.pump(const Duration(milliseconds: 300));
      expect(host.sent, isEmpty);
    });

    testWidgets(
      'two rapid Exit taps in countIn → 1 CancelPractice (M1 single-fire gate)',
      (tester) async {
        final host = _FakeSessionHost();
        addTearDown(host.close);
        host.emitState(_stateFor(PracticeSessionStatus.countIn));
        await _pumpScreen(tester, host: host);
        // First tap: opens the dialog. While it is open, a second
        // tap must be a no-op. The screen's controls row is the only
        // ElevatedButton with text "Exit" outside the dialog route, so
        // we anchor the finder on the PracticeControls widget to
        // disambiguate from the dialog's confirm button.
        final exitButton = find.descendant(
          of: find.byType(PracticeControls),
          matching: find.widgetWithText(
            ElevatedButton,
            l10nEn().practiceSessionExit,
          ),
        );
        await tester.tap(exitButton);
        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        // A second tap on the same widget is intercepted by the gate.
        await tester.tap(exitButton, warnIfMissed: false);
        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(host.sent, isEmpty, reason: 'gate fires only after confirm');
        // Confirm the dialog. Only one CancelPractice should reach the host.
        final confirm = find
            .descendant(
              of: find.byType(AlertDialog),
              matching: find.widgetWithText(
                ElevatedButton,
                l10nEn().practiceSessionExit,
              ),
            )
            .first;
        await tester.tap(confirm);
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(host.sent.length, 1);
        expect(host.sent.single, isA<CancelPractice>());
      },
    );
  });

  // -----------------------------------------------------------------
  // A5 — duplicate navigation guard
  // -----------------------------------------------------------------
  group('A5 — NavigateToResult duplicate guard', () {
    testWidgets('two NavigateToResult effects → 1 navigation call', (
      tester,
    ) async {
      final host = _FakeSessionHost();
      final nav = _RecordingNavigationSink();
      addTearDown(host.close);
      host.emitState(_stateFor(PracticeSessionStatus.running));
      await _pumpScreen(tester, host: host, navSink: nav);
      host.emitEffect(const NavigateToResult());
      host.emitEffect(const NavigateToResult());
      await tester.pump(const Duration(milliseconds: 10));
      expect(nav.calls, 1);
    });
  });
}

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

int _occurrences(String source, String needle) {
  if (needle.isEmpty) return 0;
  var from = 0;
  var count = 0;
  while (true) {
    final i = source.indexOf(needle, from);
    if (i < 0) return count;
    count++;
    from = i + needle.length;
  }
}

/// Strips Dart line and block comments from [source] while preserving
/// string literals. The shape is copied from
/// `test/features/practice/presentation/practice_presentation_guard_test.dart`
/// so the two source-only guards reason identically.
String _stripComments(String source) {
  final buf = StringBuffer();
  var i = 0;
  final n = source.length;
  while (i < n) {
    final ch = source[i];
    final next = i + 1 < n ? source[i + 1] : '';
    if (ch == '/' && next == '/') {
      while (i < n && source[i] != '\n') {
        buf.write(' ');
        i++;
      }
      continue;
    }
    if (ch == '/' && next == '*') {
      buf.write('  ');
      i += 2;
      while (i + 1 < n && !(source[i] == '*' && source[i + 1] == '/')) {
        buf.write(source[i] == '\n' ? '\n' : ' ');
        i++;
      }
      if (i + 1 < n) {
        buf.write('  ');
        i += 2;
      }
      continue;
    }
    if (ch == "'" || ch == '"') {
      final quote = ch;
      buf.write(ch);
      i++;
      while (i < n && source[i] != quote) {
        if (source[i] == r'\' && i + 1 < n) {
          buf.write(source[i]);
          buf.write(source[i + 1]);
          i += 2;
        } else {
          buf.write(source[i]);
          i++;
        }
      }
      if (i < n) {
        buf.write(source[i]);
        i++;
      }
      continue;
    }
    buf.write(ch);
    i++;
  }
  return buf.toString();
}
