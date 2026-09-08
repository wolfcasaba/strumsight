import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/practice/application/practice_catalog_controller.dart';
import 'package:strumsight/features/practice/application/practice_session_command.dart';
import 'package:strumsight/features/practice/application/practice_setup_controller.dart';
import 'package:strumsight/features/practice/domain/model/beat_position.dart';
import 'package:strumsight/features/practice/domain/model/meter.dart';
import 'package:strumsight/features/practice/domain/model/practice_definition.dart';
import 'package:strumsight/features/practice/domain/model/practice_difficulty.dart';
import 'package:strumsight/features/practice/domain/model/practice_event.dart';
import 'package:strumsight/features/practice/domain/model/practice_mode.dart';
import 'package:strumsight/features/practice/domain/model/practice_session_config.dart';
import 'package:strumsight/features/practice/domain/model/practice_source.dart';
import 'package:strumsight/features/practice/domain/model/practice_validation.dart';
import 'package:strumsight/features/practice/domain/model/scoring_profile.dart';
import 'package:strumsight/features/practice/domain/model/tempo.dart';
import 'package:strumsight/features/practice/domain/repository/practice_catalog_repository.dart';
import 'package:strumsight/features/practice/presentation/practice_route_args.dart';
import 'package:strumsight/features/practice/presentation/screens/practice_setup_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/l10n/app_localizations_en.dart';

import '../../../support/preference_store.dart';

/// Minimal hand-built definition for the Setup screen tests. The
/// definition is wired only as far as the Setup needs; nothing is
/// load-bearing for the session runtime here.
PracticeDefinition _definition({
  required String id,
  required PracticeMode mode,
  required Meter meter,
  required double bpm,
  String displayTitle = 'Fixture',
}) {
  return PracticeDefinition(
    id: id,
    schemaVersion: 1,
    titleKey: 'practiceCatalogTestSetupTitle',
    descriptionKey: 'practiceCatalogTestSetupDescription',
    mode: mode,
    source: PracticeSource.builtin,
    meter: meter,
    defaultTempo: Tempo(bpm),
    totalBeats: BeatPosition.quarters(16),
    events: List<PracticeEvent>.unmodifiable([
      for (var i = 0; i < 16; i++)
        PracticeEvent(
          id: '$id.e$i',
          position: BeatPosition.quarters(i),
          direction: StrumDirection.down,
        ),
    ]),
    scoringProfile: ScoringProfile.legacyLearnParity,
    skillTags: const ['test'],
    displayTitle: displayTitle,
  );
}

class _SingleDefRepository implements PracticeCatalogRepository {
  const _SingleDefRepository(this.definition);

  final PracticeDefinition definition;

  @override
  List<PracticeDefinition> all() =>
      List<PracticeDefinition>.unmodifiable([definition]);
  @override
  PracticeDefinition? byId(String id) =>
      id == definition.id ? definition : null;
  @override
  List<PracticeDefinition> byMode(PracticeMode mode) => definition.mode == mode
      ? List<PracticeDefinition>.unmodifiable([definition])
      : const <PracticeDefinition>[];
  @override
  List<PracticeDefinition> byDifficulty(PracticeDifficulty difficulty) =>
      const <PracticeDefinition>[];
}

class _RecordingSink {
  _RecordingSink();
  int calls = 0;
  final List<PreparePractice> commands = <PreparePractice>[];

  void call(PreparePractice command) {
    calls++;
    commands.add(command);
  }
}

ProviderContainer _container({
  required _SingleDefRepository repository,
  _RecordingSink? sinkOverride,
}) {
  return ProviderContainer(
    overrides: [
      ...preferenceOverrides(),
      // practiceCatalogRepositoryProvider lives in the application folder;
      // override it so the Setup screen finds the test definition.
      practiceCatalogRepositoryProvider.overrideWithValue(repository),
      if (sinkOverride != null)
        practicePrepareSinkProvider.overrideWithValue(sinkOverride.call),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('A4 controller matrix — domain-derived limits only', () {
    test('BPM 29 invalid, 30 valid, 300 valid, 301 invalid', () {
      final def = _definition(
        id: 'fixture.tempo',
        mode: PracticeMode.strumPattern,
        meter: const Meter(beatsPerBar: 4),
        bpm: 100,
      );
      final container = _container(repository: _SingleDefRepository(def));
      addTearDown(container.dispose);
      final controller = container.read(
        practiceSetupControllerProvider(def).notifier,
      );

      controller.setTempoBpm(29);
      expect(
        container.read(practiceSetupControllerProvider(def)).isValid,
        isFalse,
      );
      expect(
        container
            .read(practiceSetupControllerProvider(def))
            .failures
            .map((f) => f.code)
            .first,
        PracticeValidationCode.tempoBpmOutOfRange,
      );

      controller.setTempoBpm(30);
      expect(
        container.read(practiceSetupControllerProvider(def)).isValid,
        isTrue,
      );

      controller.setTempoBpm(300);
      expect(
        container.read(practiceSetupControllerProvider(def)).isValid,
        isTrue,
      );

      controller.setTempoBpm(301);
      expect(
        container.read(practiceSetupControllerProvider(def)).isValid,
        isFalse,
      );
    });

    test('count-in bars -1 / 0 / 2 / 4 / 5 — only 0..4 are valid', () {
      final def = _definition(
        id: 'fixture.countin',
        mode: PracticeMode.strumPattern,
        meter: const Meter(beatsPerBar: 4),
        bpm: 100,
      );
      final container = _container(repository: _SingleDefRepository(def));
      addTearDown(container.dispose);

      for (final n in <int>[-1, 0, 2, 4, 5]) {
        container
            .read(practiceSetupControllerProvider(def).notifier)
            .setCountInBars(n);
        final isValid = container
            .read(practiceSetupControllerProvider(def))
            .isValid;
        final expected = n >= 0 && n <= 4;
        expect(isValid, expected, reason: 'countInBars=$n');
      }
    });

    test('loop count 0 / 1 / 32 / 33 — only 1..32 are valid', () {
      final def = _definition(
        id: 'fixture.loop',
        mode: PracticeMode.strumPattern,
        meter: const Meter(beatsPerBar: 4),
        bpm: 100,
      );
      final container = _container(repository: _SingleDefRepository(def));
      addTearDown(container.dispose);

      for (final n in <int>[0, 1, 32, 33]) {
        container
            .read(practiceSetupControllerProvider(def).notifier)
            .setLoopCount(n);
        final isValid = container
            .read(practiceSetupControllerProvider(def))
            .isValid;
        final expected = n >= 1 && n <= 32;
        expect(isValid, expected, reason: 'loopCount=$n');
      }
    });

    test('default config is seeded from the definition', () {
      final def = _definition(
        id: 'fixture.seed',
        mode: PracticeMode.strumPattern,
        meter: const Meter(beatsPerBar: 4),
        bpm: 88,
      );
      final container = _container(repository: _SingleDefRepository(def));
      addTearDown(container.dispose);

      final state = container.read(practiceSetupControllerProvider(def));
      expect(state.config.definitionId, def.id);
      expect(state.config.definitionSnapshotVersion, def.schemaVersion);
      expect(state.config.effectiveTempo.bpm, 88);
      expect(state.config.scoringProfileId, def.scoringProfile.id);
    });
  });

  group('A5 mode-specific visibility', () {
    Future<void> pumpSetup(
      WidgetTester tester, {
      required PracticeDefinition def,
    }) async {
      final container = _container(repository: _SingleDefRepository(def));
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: PracticeSetupScreen(
              argsOverride: PracticeSetupArgs(
                request: PracticeSetupRequest.hasId,
                definitionId: def.id,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('Free Practice hides the scoring profile row', (tester) async {
      final def = _definition(
        id: 'fixture.free',
        mode: PracticeMode.freePractice,
        meter: const Meter(beatsPerBar: 4),
        bpm: 80,
      );
      await pumpSetup(tester, def: def);
      expect(find.text('Scoring profile'), findsNothing);
    });

    testWidgets('Rhythm-only hides the chord-hint control', (tester) async {
      final def = _definition(
        id: 'fixture.rhythm',
        mode: PracticeMode.rhythmOnly,
        meter: const Meter(beatsPerBar: 4),
        bpm: 70,
      );
      await pumpSetup(tester, def: def);
      expect(find.text('Show chord hint'), findsNothing);
    });

    testWidgets('strumPattern shows the scoring profile row', (tester) async {
      final def = _definition(
        id: 'fixture.strum',
        mode: PracticeMode.strumPattern,
        meter: const Meter(beatsPerBar: 4),
        bpm: 70,
      );
      await pumpSetup(tester, def: def);
      // The form is long; the scoring-profile row is below the default
      // 800x600 fold. Scroll until visible.
      await tester.scrollUntilVisible(
        find.text('Scoring profile'),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Scoring profile'), findsOneWidget);
    });

    testWidgets('the scoring profile row shows a localized label, never the '
        'raw profile id (audit H14)', (tester) async {
      final def = _definition(
        id: 'fixture.strum.h14',
        mode: PracticeMode.strumPattern,
        meter: const Meter(beatsPerBar: 4),
        bpm: 70,
      );
      await pumpSetup(tester, def: def);
      await tester.scrollUntilVisible(
        find.text('Scoring profile'),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.text(ScoringProfile.legacyLearnParity.id),
        findsNothing,
        reason: 'H14: "legacyLearnParity" is a machine id, not user copy',
      );
      expect(
        find.text(AppLocalizationsEn().practiceScoringProfileLegacyLearnParity),
        findsOneWidget,
      );
    });

    test('every built-in profile maps to its own localized label, and an '
        'unknown one falls back instead of leaking its id', () {
      final l10n = AppLocalizationsEn();
      final labels = <String>{
        practiceScoringProfileLabel(l10n, ScoringProfile.legacyLearnParity),
        practiceScoringProfileLabel(l10n, ScoringProfile.chordChangeDefault),
        practiceScoringProfileLabel(
          l10n,
          ScoringProfile.chordProgressionDefault,
        ),
        practiceScoringProfileLabel(l10n, ScoringProfile.rhythmOnlyDefault),
        practiceScoringProfileLabel(l10n, ScoringProfile.freePracticeOpen),
      };
      expect(labels, hasLength(5), reason: 'no two profiles share a label');
      const unknown = ScoringProfile(
        id: 'someFutureProfile',
        matchWindow: Duration(milliseconds: 280),
        perfectWindow: Duration(milliseconds: 50),
        goodWindow: Duration(milliseconds: 120),
        extraStrumPolicy: ExtraStrumPolicy.ignore,
        weights: {PracticeScoreDimension.rhythm: 100},
        completionThresholdPercent: 85,
        overallThresholdPercent: 70,
      );
      final fallback = practiceScoringProfileLabel(l10n, unknown);
      expect(fallback, l10n.practiceScoringProfileCustom);
      expect(fallback.contains(unknown.id), isFalse);
    });
  });

  group('A6 Start command shape', () {
    test('start() sends exactly one PreparePractice with the UI fields', () {
      final def = _definition(
        id: 'fixture.start',
        mode: PracticeMode.strumPattern,
        meter: const Meter(beatsPerBar: 4),
        bpm: 100,
      );
      final sink = _RecordingSink();
      final container = _container(
        repository: _SingleDefRepository(def),
        sinkOverride: sink,
      );
      addTearDown(container.dispose);

      final controller = container.read(
        practiceSetupControllerProvider(def).notifier,
      );
      // Drive the UI a little — different bpm, count-in, loop — so the
      // test verifies the command field round-trip rather than the seed
      // defaults.
      controller.setTempoBpm(120);
      controller.setCountInBars(2);
      controller.setLoopCount(4);
      controller.setMetronomeEnabled(false);
      controller.setAccentEnabled(true);
      controller.setChordHintEnabled(false);

      final sent = controller.start();

      expect(sent, isTrue);
      expect(sink.calls, 1, reason: 'exactly one PreparePractice');
      final cmd = sink.commands.single;
      expect(cmd.definition.id, def.id);
      expect(cmd.config.effectiveTempo.bpm, 120);
      expect(cmd.config.countInBars, 2);
      expect(cmd.config.loopCount, 4);
      expect(cmd.config.metronomeEnabled, isFalse);
      expect(cmd.config.accentEnabled, isTrue);
    });

    testWidgets('Start button is disabled when config is invalid', (
      tester,
    ) async {
      final def = _definition(
        id: 'fixture.invalid',
        mode: PracticeMode.strumPattern,
        meter: const Meter(beatsPerBar: 4),
        bpm: 100,
      );
      final container = _container(repository: _SingleDefRepository(def));
      addTearDown(container.dispose);

      // Force the controller into an invalid state via the public API.
      container
          .read(practiceSetupControllerProvider(def).notifier)
          .setCountInBars(5);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: PracticeSetupScreen(
              argsOverride: PracticeSetupArgs(
                request: PracticeSetupRequest.hasId,
                definitionId: def.id,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // The Start button + error live at the bottom of a long form —
      // scroll them into the viewport before asserting.
      await tester.scrollUntilVisible(
        find.widgetWithText(FilledButton, 'Start practice'),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      final start = find.widgetWithText(FilledButton, 'Start practice');
      expect(start, findsOneWidget);
      final button = tester.widget<FilledButton>(start);
      expect(button.onPressed, isNull);
      // The error text is below the button — scroll a bit more so the
      // bottom of the form is also visible.
      await tester.scrollUntilVisible(
        find.text('Count-in bars must be between 0 and 4.'),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.text('Count-in bars must be between 0 and 4.'),
        findsOneWidget,
      );
    });
  });

  testWidgets('unknown id shows the localized error state', (tester) async {
    final def = _definition(
      id: 'fixture.something',
      mode: PracticeMode.strumPattern,
      meter: const Meter(beatsPerBar: 4),
      bpm: 100,
    );
    final container = _container(repository: _SingleDefRepository(def));
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const PracticeSetupScreen(
            argsOverride: PracticeSetupArgs(
              request: PracticeSetupRequest.hasId,
              definitionId: 'does.not.exist',
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Practice unavailable'), findsOneWidget);
    expect(find.text("This practice isn't available."), findsOneWidget);
  });

  testWidgets('missing id shows the localized error state', (tester) async {
    final def = _definition(
      id: 'fixture.something',
      mode: PracticeMode.strumPattern,
      meter: const Meter(beatsPerBar: 4),
      bpm: 100,
    );
    final container = _container(repository: _SingleDefRepository(def));
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const PracticeSetupScreen(
            argsOverride: PracticeSetupArgs(
              request: PracticeSetupRequest.missing,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Practice unavailable'), findsOneWidget);
  });

  testWidgets(
    'the meter readout renders the definition meter (3/4, 6/8, 4/4)',
    (tester) async {
      for (final m in const [
        Meter(beatsPerBar: 4),
        Meter(beatsPerBar: 3),
        Meter(beatsPerBar: 6, beatUnit: 8),
      ]) {
        final def = _definition(
          id: 'fixture.meter.${m.beatsPerBar}.${m.beatUnit}',
          mode: PracticeMode.strumPattern,
          meter: m,
          bpm: 90,
        );
        final container = _container(repository: _SingleDefRepository(def));
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: PracticeSetupScreen(
                argsOverride: PracticeSetupArgs(
                  request: PracticeSetupRequest.hasId,
                  definitionId: def.id,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(
          find.text('${m.beatsPerBar}/${m.beatUnit}'),
          findsOneWidget,
          reason: 'meter ${m.beatsPerBar}/${m.beatUnit}',
        );
      }
    },
  );

  group('MINOR-1 — the readiness tuning entry is reachable from Setup', () {
    testWidgets('renders the tuning entry and tapping it opens '
        'AppRoutes.practiceTuner (SDD UI-18 "a tuning warningból közvetlen '
        'Tuner nyitható", review E13-R21 MINOR-1)', (tester) async {
      final def = _definition(
        id: 'fixture.tuning-entry',
        mode: PracticeMode.strumPattern,
        meter: const Meter(beatsPerBar: 4),
        bpm: 100,
      );
      final container = _container(repository: _SingleDefRepository(def));
      addTearDown(container.dispose);
      final router = GoRouter(
        initialLocation: '/practice/setup',
        routes: [
          GoRoute(
            path: '/practice/setup',
            builder: (context, state) => PracticeSetupScreen(
              argsOverride: PracticeSetupArgs(
                request: PracticeSetupRequest.hasId,
                definitionId: def.id,
              ),
            ),
          ),
          GoRoute(
            path: '/practice/tuner',
            builder: (context, state) =>
                const Scaffold(body: Center(child: Text('TUNER SENTINEL'))),
          ),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('practice-readiness-tuning')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('practice-readiness-tuning')));
      await tester.pumpAndSettle();

      expect(find.text('TUNER SENTINEL'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------
  // Audit L8 / U3 / U1 — beginner defaults, one label per setting, and a
  // Start CTA that does not hide below the fold.
  // -------------------------------------------------------------------
  group('audit — setup defaults and layout', () {
    PracticeDefinition strumDefinition() => _definition(
      id: 'fixture.audit',
      mode: PracticeMode.strumPattern,
      meter: const Meter(beatsPerBar: 4),
      bpm: 90,
    );

    Future<void> pumpSetup(
      WidgetTester tester, {
      required PracticeDefinition def,
      Size surface = const Size(500, 1400),
    }) async {
      final container = _container(repository: _SingleDefRepository(def));
      addTearDown(container.dispose);
      tester.view.physicalSize = surface;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: PracticeSetupScreen(
              argsOverride: PracticeSetupArgs(
                request: PracticeSetupRequest.hasId,
                definitionId: def.id,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    test('L8 — the seed is beginner-friendly, not the bare minimums', () {
      final def = strumDefinition();
      final container = _container(repository: _SingleDefRepository(def));
      addTearDown(container.dispose);

      final state = container.read(practiceSetupControllerProvider(def));
      final config = state.config;
      // A first session gets a preparation bar, enough repetitions to feel
      // a change, and the chord hint already on.
      expect(config.countInBars, practiceDefaultCountInBars);
      expect(config.countInBars, greaterThanOrEqualTo(1));
      expect(config.loopCount, practiceDefaultLoopCount);
      expect(config.loopCount, greaterThanOrEqualTo(2));
      expect(config.expectedChordHintEnabled, isTrue);
      expect(
        container.read(practiceSetupControllerProvider(def)).isValid,
        isTrue,
        reason: 'the new defaults must sit inside the domain range',
      );
    });

    test('L8 — the ALLOWED RANGE is untouched: the minimums stay valid', () {
      final def = strumDefinition();
      final container = _container(repository: _SingleDefRepository(def));
      addTearDown(container.dispose);
      final controller = container.read(
        practiceSetupControllerProvider(def).notifier,
      );

      controller.setCountInBars(PracticeSessionConfig.minimumCountInBars);
      controller.setLoopCount(PracticeSessionConfig.minimumLoopCount);
      controller.setChordHintEnabled(false);
      final state = container.read(practiceSetupControllerProvider(def));
      expect(state.isValid, isTrue);
      expect(state.config.countInBars, 0);
      expect(state.config.loopCount, 1);
      expect(state.config.expectedChordHintEnabled, isFalse);
    });

    testWidgets('U3 — every setting is named exactly once', (tester) async {
      final l10n = AppLocalizationsEn();
      await pumpSetup(tester, def: strumDefinition());

      // The row label names the setting; the numeric field next to it
      // carries only the unit. Before the fix the field fell back to the
      // row label and printed it a second time, side by side.
      expect(find.text(l10n.practiceSetupCountInLabel), findsOneWidget);
      expect(find.text(l10n.practiceSetupLoopLabel), findsOneWidget);
      expect(find.text(l10n.practiceSetupBpmLabel), findsOneWidget);
      expect(find.text(l10n.practiceSetupCountInUnit), findsOneWidget);
      expect(find.text(l10n.practiceSetupLoopUnit), findsOneWidget);
      expect(find.text(l10n.practiceSetupBpmUnit), findsOneWidget);
    });

    testWidgets('U1 — the Start CTA is on screen without scrolling', (
      tester,
    ) async {
      final l10n = AppLocalizationsEn();
      // A small, compact phone viewport — the form is far taller than this.
      await pumpSetup(
        tester,
        def: strumDefinition(),
        surface: const Size(360, 640),
      );

      final start = find.widgetWithText(FilledButton, l10n.practiceSetupStart);
      expect(start, findsOneWidget);
      // The CTA is NOT a child of the scrolling form any more: no amount
      // of scrolling can hide it.
      expect(
        find.descendant(of: find.byType(ListView), matching: start),
        findsNothing,
      );
      // …and it is drawn inside the viewport, at a tappable height.
      final rect = tester.getRect(start);
      expect(rect.bottom, lessThanOrEqualTo(640.0));
      expect(rect.top, greaterThanOrEqualTo(0.0));
      expect(rect.height, greaterThanOrEqualTo(48.0));
      // The pointer really lands on the CTA where it is drawn — nothing
      // (a system inset, the list content) covers it.
      final RenderBox box = tester.renderObject(start);
      final hit = tester.hitTestOnBinding(tester.getCenter(start));
      expect(
        hit.path.any((entry) => identical(entry.target, box)),
        isTrue,
        reason: 'the pinned Start CTA must be hit-testable where it is drawn',
      );
    });
  });
}
