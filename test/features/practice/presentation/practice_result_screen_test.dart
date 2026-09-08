import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/practice/application/practice_session_command.dart';
import 'package:strumsight/features/practice/application/practice_session_providers.dart';
import 'package:strumsight/features/practice/application/practice_setup_controller.dart';
import 'package:strumsight/features/practice/domain/model/beat_position.dart';
import 'package:strumsight/features/practice/domain/model/meter.dart';
import 'package:strumsight/features/practice/domain/model/practice_definition.dart';
import 'package:strumsight/features/practice/domain/model/practice_event.dart';
import 'package:strumsight/features/practice/domain/model/practice_history_entry.dart';
import 'package:strumsight/features/practice/domain/model/practice_metric_snapshot.dart';
import 'package:strumsight/features/practice/domain/model/practice_mode.dart';
import 'package:strumsight/features/practice/domain/model/practice_session_config.dart';
import 'package:strumsight/features/practice/domain/model/practice_source.dart';
import 'package:strumsight/features/practice/domain/model/scoring_profile.dart';
import 'package:strumsight/features/practice/domain/model/tempo.dart';
import 'package:strumsight/features/practice/presentation/practice_effect_listener.dart';
import 'package:strumsight/features/practice/presentation/screens/practice_result_screen.dart';
import 'package:strumsight/features/practice/presentation/screens/practice_setup_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/l10n/app_localizations_en.dart';
import 'package:strumsight/core/design_system/themes/ss_light_theme.dart';

import '../../../support/preference_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  AppLocalizations l10n() => AppLocalizationsEn();

  Future<void> pumpResult(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: preferenceOverrides(),
        child: MaterialApp(
          theme: SsLightTheme.data(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: child,
        ),
      ),
    );
    await tester.pump();
  }

  group('A1 — visibility matrix', () {
    testWidgets('Strum Pattern: chord block is NOT in the tree', (
      tester,
    ) async {
      final entry = _entry(PracticeMode.strumPattern);
      await pumpResult(tester, PracticeResultScreen(entry: entry));
      // Chord is not applicable to strum-pattern; the card never renders it.
      expect(find.text(l10n().practiceResultChord), findsNothing);
    });

    testWidgets('Chord Changes: direction is hidden', (tester) async {
      final entry = _entry(PracticeMode.chordChanges);
      await pumpResult(tester, PracticeResultScreen(entry: entry));
      expect(find.text(l10n().practiceResultDirection), findsNothing);
    });

    testWidgets('Chord Progression: all four dimensions render', (
      tester,
    ) async {
      final entry = _entry(PracticeMode.chordProgression);
      await pumpResult(tester, PracticeResultScreen(entry: entry));
      expect(find.text(l10n().practiceResultOverall), findsOneWidget);
      expect(find.text(l10n().practiceResultRhythm), findsOneWidget);
      expect(find.text(l10n().practiceResultDirection), findsOneWidget);
      expect(find.text(l10n().practiceResultChord), findsOneWidget);
    });

    testWidgets('Free Practice: NO overall/rhythm/direction/chord cards', (
      tester,
    ) async {
      final entry = _entry(PracticeMode.freePractice);
      await pumpResult(tester, PracticeResultScreen(entry: entry));
      expect(find.text(l10n().practiceResultOverall), findsNothing);
      expect(find.text(l10n().practiceResultRhythm), findsNothing);
      expect(find.text(l10n().practiceResultDirection), findsNothing);
      expect(find.text(l10n().practiceResultChord), findsNothing);
    });
  });

  group('A2 — InsufficientData is NOT rendered as a percentage', () {
    testWidgets(
      'a dimension in InsufficientData shows the "not enough data" string',
      (tester) async {
        final entry = _entry(PracticeMode.chordProgression).copyWith(
          finalMetricSnapshot: const PracticeMetricSnapshot(
            completion: PracticeMetricDimensionAvailable(0.9),
            rhythm: PracticeMetricDimensionAvailable(0.85),
            direction: PracticeMetricDimensionInsufficientData(
              'practice.metric.insufficient_samples',
            ),
            chord: PracticeMetricDimensionAvailable(0.95),
            overall: PracticeMetricDimensionAvailable(0.9),
          ),
        );
        await pumpResult(tester, PracticeResultScreen(entry: entry));
        // The "not enough data" cell renders once for direction.
        expect(
          find.text(l10n().practiceResultInsufficientData),
          findsOneWidget,
        );
        // No percentage is rendered for the direction row.
        final directionLabel = find.text(l10n().practiceResultDirection);
        final percentRendered = find.descendant(
          of: directionLabel,
          matching: find.byWidgetPredicate(
            (w) => w is Text && w.data != null && w.data!.contains('%'),
          ),
        );
        expect(percentRendered, findsNothing);
      },
    );
  });

  group('A3 — Free Practice result is score-free', () {
    testWidgets(
      'no overall / pass-fail / accuracy / combo tiles, but the fact tiles render',
      (tester) async {
        final entry = _entry(PracticeMode.freePractice).copyWith(
          attemptsCount: 12,
          activeDuration: const Duration(minutes: 2, seconds: 30),
        );
        await pumpResult(tester, PracticeResultScreen(entry: entry));
        // No overall / pass-fail / accuracy tiles are rendered.
        expect(find.text(l10n().practiceResultOverall), findsNothing);
        // The two fact tiles are present.
        expect(
          find.text(l10n().practiceFreePracticeActiveDuration),
          findsOneWidget,
        );
        expect(
          find.text(l10n().practiceFreePracticeStrumCount),
          findsOneWidget,
        );
        // Active duration renders as "2m 30s".
        expect(find.text('2m 30s'), findsOneWidget);
        expect(find.text('12'), findsOneWidget);
      },
    );
  });

  group('E15-R04 — design-system migration', () {
    testWidgets(
      'PracticeResultFallback (no entry) renders the informational state, '
      'no action and no navigation (E15-R04 review MAJOR-3b: this fallback '
      'never navigated pre-migration; adding one would be a behaviour '
      'change in an appearance-only round)',
      (tester) async {
        await pumpResult(tester, const PracticeResultFallback());
        expect(
          find.text(l10n().practiceResultUnavailableTitle),
          findsOneWidget,
        );
        expect(find.text(l10n().practiceResultUnavailableBody), findsOneWidget);
        expect(
          find.byKey(const ValueKey('ss-empty-state-action')),
          findsNothing,
        );
        expect(find.byType(FilledButton), findsNothing);
        expect(find.byType(TextButton), findsNothing);
        expect(find.byType(ElevatedButton), findsNothing);
      },
    );

    for (final locale in [const Locale('en'), const Locale('hu')]) {
      testWidgets('textScaler 2.0 renders without overflow — Chord Progression '
          '(${locale.languageCode})', (tester) async {
        tester.view.platformDispatcher.textScaleFactorTestValue = 2.0;
        addTearDown(
          tester.view.platformDispatcher.clearTextScaleFactorTestValue,
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: preferenceOverrides(),
            child: MaterialApp(
              theme: SsLightTheme.data(),
              locale: locale,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: PracticeResultScreen(
                entry: _entry(PracticeMode.chordProgression),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      });

      testWidgets(
        'textScaler 2.0 renders the PracticeResultFallback without overflow '
        '(${locale.languageCode})',
        (tester) async {
          tester.view.platformDispatcher.textScaleFactorTestValue = 2.0;
          addTearDown(
            tester.view.platformDispatcher.clearTextScaleFactorTestValue,
          );
          await tester.pumpWidget(
            ProviderScope(
              overrides: preferenceOverrides(),
              child: MaterialApp(
                theme: SsLightTheme.data(),
                locale: locale,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: const PracticeResultFallback(),
              ),
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
        },
      );
    }
  });

  // -------------------------------------------------------------------
  // H22 — the screen title is not repeated in the body
  // -------------------------------------------------------------------
  group('H22 — no duplicated screen title', () {
    testWidgets('an entry without its own title renders "Practice result" '
        'exactly once (the app bar)', (tester) async {
      final entry = _entry(PracticeMode.strumPattern, displayTitle: '');
      await pumpResult(tester, PracticeResultScreen(entry: entry));
      expect(
        find.text(l10n().practiceResultTitle),
        findsOneWidget,
        reason:
            'H22: the header used to echo the app-bar title as the first '
            'body line whenever the entry had no title of its own.',
      );
    });

    testWidgets('an entry WITH a title still shows it under the app bar', (
      tester,
    ) async {
      final entry = _entry(PracticeMode.strumPattern);
      await pumpResult(tester, PracticeResultScreen(entry: entry));
      expect(find.text(entry.displayTitle), findsOneWidget);
      expect(find.text(l10n().practiceResultTitle), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------
  // L3 — "Practice again" restarts the same drill, same settings
  // -------------------------------------------------------------------
  group('L3 — Practice again restarts the drill', () {
    testWidgets('with the finished session still active it re-dispatches the '
        'IDENTICAL definition + config and opens the session', (tester) async {
      final entry = _entry(PracticeMode.strumPattern);
      final definition = _definitionFor(entry.definitionId);
      final config = _configFor(entry.definitionId);
      final commands = <PreparePractice>[];
      var sessionNavigations = 0;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...preferenceOverrides(),
            // The activation chain is exercised end-to-end by
            // `practice_setup_navigation_test.dart`; here the host is
            // stubbed out so the cell measures the restart hand-off only.
            practiceSessionHostProvider.overrideWithValue(null),
            practiceActiveSessionInputsProvider.overrideWith(
              () => _FixedInputs((definition: definition, config: config)),
            ),
            practicePrepareSinkProvider.overrideWithValue(commands.add),
            practiceSessionNavigationSinkProvider.overrideWithValue(
              () => sessionNavigations++,
            ),
          ],
          child: MaterialApp(
            theme: SsLightTheme.data(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: PracticeResultScreen(entry: entry),
          ),
        ),
      );
      await tester.pump();

      final cta = find.text(l10n().practiceResultNextStepCta);
      await tester.ensureVisible(cta);
      await tester.pumpAndSettle();
      await tester.tap(cta);
      await tester.pumpAndSettle();

      expect(commands, hasLength(1));
      expect(commands.single.definition, definition);
      expect(
        commands.single.config,
        config,
        reason: 'L3: "again" means the SAME settings, not a fresh setup',
      );
      expect(sessionNavigations, 1);
      expect(
        find.byType(PracticeSetupScreen),
        findsNothing,
        reason: 'L3: the user must not be dropped back on Practice setup',
      );
    });

    testWidgets('inputs belonging to ANOTHER definition are not reused', (
      tester,
    ) async {
      final entry = _entry(PracticeMode.strumPattern);
      const otherId = 'some-other-definition';
      final commands = <PreparePractice>[];
      var sessionNavigations = 0;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...preferenceOverrides(),
            practiceSessionHostProvider.overrideWithValue(null),
            practiceActiveSessionInputsProvider.overrideWith(
              () => _FixedInputs((
                definition: _definitionFor(otherId),
                config: _configFor(otherId),
              )),
            ),
            practicePrepareSinkProvider.overrideWithValue(commands.add),
            practiceSessionNavigationSinkProvider.overrideWithValue(
              () => sessionNavigations++,
            ),
          ],
          child: MaterialApp(
            theme: SsLightTheme.data(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: PracticeResultScreen(entry: entry),
          ),
        ),
      );
      await tester.pump();

      final cta = find.text(l10n().practiceResultNextStepCta);
      await tester.ensureVisible(cta);
      await tester.pumpAndSettle();
      await tester.tap(cta);
      await tester.pumpAndSettle();

      // Nothing to restart from — the user goes to Setup for THIS entry's
      // definition rather than silently replaying a different drill.
      expect(commands, isEmpty);
      expect(sessionNavigations, 0);
      expect(find.byType(PracticeSetupScreen), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------
  // Audit U2 / U10 / U11 — action hierarchy, empty share, reward copy
  // -------------------------------------------------------------------
  group('audit — result actions', () {
    /// A viewport tall enough that every action below the fold is built —
    /// the assertions are about hierarchy and enablement, not scrolling.
    Future<void> pumpTall(WidgetTester tester, Widget child) async {
      tester.view.physicalSize = const Size(500, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await pumpResult(tester, child);
    }

    testWidgets('U2 — exactly ONE primary (filled) button in the actions', (
      tester,
    ) async {
      await pumpTall(
        tester,
        PracticeResultScreen(entry: _entry(PracticeMode.strumPattern)),
      );
      // "Practice again" is the single filled action; every other action
      // on the screen (Share, History, Speed Builder) is outlined.
      final primaries = find.byWidgetPredicate(
        (w) => w is FilledButton || w is ElevatedButton,
        description: 'filled/elevated (primary) buttons',
      );
      expect(primaries, findsOneWidget);
      expect(
        find.ancestor(
          of: find.text(l10n().practiceResultNextStepCta),
          matching: primaries,
        ),
        findsOneWidget,
        reason: 'the one primary must be "Practice again"',
      );
      expect(
        find.byWidgetPredicate((w) => w is OutlinedButton),
        findsWidgets,
        reason: 'Share / History / Speed Builder stay secondary',
      );
    });

    testWidgets('U10 — a result with nothing detected disables Share', (
      tester,
    ) async {
      // 0 of 16 targets resolved: the share card would print "0/16" with
      // no evidence behind it.
      final entry = _entry(
        PracticeMode.strumPattern,
      ).copyWith(resolvedTargets: 0);
      await pumpTall(tester, PracticeResultScreen(entry: entry));

      final share = find.ancestor(
        of: find.text(l10n().practiceResultShareCta),
        matching: find.byWidgetPredicate((w) => w is OutlinedButton),
      );
      expect(share, findsOneWidget);
      expect(tester.widget<OutlinedButton>(share).onPressed, isNull);
      // A disabled control still says why.
      expect(find.text(l10n().practiceResultShareUnavailable), findsOneWidget);
      // Tapping it cannot open the share projection either.
      await tester.tap(share, warnIfMissed: false);
      await tester.pump();
      expect(find.text(l10n().practiceResultShareSummaryTitle), findsNothing);
    });

    testWidgets('U10 — a normal result keeps Share enabled', (tester) async {
      await pumpTall(
        tester,
        PracticeResultScreen(entry: _entry(PracticeMode.strumPattern)),
      );
      final share = find.ancestor(
        of: find.text(l10n().practiceResultShareCta),
        matching: find.byWidgetPredicate((w) => w is OutlinedButton),
      );
      expect(tester.widget<OutlinedButton>(share).onPressed, isNotNull);
      expect(find.text(l10n().practiceResultShareUnavailable), findsNothing);
      await tester.tap(share);
      await tester.pump();
      expect(find.text(l10n().practiceResultShareSummaryTitle), findsOneWidget);
    });

    test('U10 — the predicate follows the model, not the mode', () {
      final scored = _entry(PracticeMode.strumPattern);
      expect(practiceResultHasShareableEvidence(scored), isTrue);
      expect(
        practiceResultHasShareableEvidence(scored.copyWith(resolvedTargets: 0)),
        isFalse,
      );
      // Free Practice sets no targets — its evidence is the attempt count.
      final free = _entry(PracticeMode.freePractice).copyWith(totalTargets: 0);
      expect(
        practiceResultHasShareableEvidence(free.copyWith(attemptsCount: 3)),
        isTrue,
      );
      expect(
        practiceResultHasShareableEvidence(free.copyWith(attemptsCount: 0)),
        isFalse,
      );
    });

    testWidgets('U11 — an empty reward is a settled fact, not a "yet"', (
      tester,
    ) async {
      await pumpTall(
        tester,
        PracticeResultScreen(entry: _entry(PracticeMode.strumPattern)),
      );
      expect(find.text(l10n().practiceRewardNone), findsOneWidget);
      expect(
        find.text(l10n().practiceResultRewardNone),
        findsNothing,
        reason: 'the old copy promised a reward that is never coming',
      );
      expect(l10n().practiceRewardNone.toLowerCase(), isNot(contains('yet')));
    });
  });
}

/// A [PracticeActiveSessionInputsController] pinned to one value, so a
/// widget test can describe "the session that just finished" without
/// building the whole session runtime.
class _FixedInputs extends PracticeActiveSessionInputsController {
  _FixedInputs(this.inputs);

  final PracticeSessionInputs inputs;

  @override
  PracticeSessionInputs? build() => inputs;
}

PracticeDefinition _definitionFor(String id) => PracticeDefinition(
  id: id,
  schemaVersion: 1,
  titleKey: 'practiceCatalogTestSetupTitle',
  descriptionKey: 'practiceCatalogTestSetupDescription',
  mode: PracticeMode.strumPattern,
  source: PracticeSource.builtin,
  meter: const Meter(beatsPerBar: 4),
  defaultTempo: const Tempo(100),
  totalBeats: BeatPosition.quarters(16),
  events: List<PracticeEvent>.unmodifiable([
    for (var i = 0; i < 4; i++)
      PracticeEvent(
        id: '$id.e$i',
        position: BeatPosition.quarters(i),
        direction: StrumDirection.down,
      ),
  ]),
  scoringProfile: ScoringProfile.legacyLearnParity,
  skillTags: const ['test'],
  displayTitle: 'Restart fixture',
);

PracticeSessionConfig _configFor(String id) => PracticeSessionConfig(
  definitionId: id,
  definitionSnapshotVersion: 1,
  effectiveTempo: const Tempo(100),
  countInBars: 1,
  loopCount: 2,
  metronomeEnabled: true,
  accentEnabled: false,
  backingEnabled: false,
  scoringProfileId: ScoringProfile.legacyLearnParity.id,
  inputLatency: Duration.zero,
  visualLatency: Duration.zero,
  expectedChordHintEnabled: true,
  sessionTimeout: const Duration(minutes: 5),
  reducedMotion: false,
);

PracticeHistoryEntry _entry(PracticeMode mode, {String? displayTitle}) {
  return PracticeHistoryEntry(
    id: 'result-${mode.code}',
    modeCode: mode.code,
    sourceCode: PracticeSource.builtin.code,
    createdAt: DateTime(2026, 8, 1, 12, 0),
    definitionId: 'd-${mode.code}',
    displayTitle: displayTitle ?? 'fixture-${mode.code}',
    finishReasonCode: 'userFinished',
    activeDuration: const Duration(seconds: 30),
    pausedDuration: Duration.zero,
    attemptsCount: 1,
    finalMetricSnapshot: const PracticeMetricSnapshot(
      completion: PracticeMetricDimensionAvailable(0.9),
      rhythm: PracticeMetricDimensionAvailable(0.85),
      direction: PracticeMetricDimensionAvailable(0.95),
      chord: PracticeMetricDimensionAvailable(0.92),
      overall: PracticeMetricDimensionAvailable(0.9),
    ),
    totalTargets: 16,
    resolvedTargets: 14,
    scorePoints: 800,
    maxCombo: 12,
    meanAbsoluteOffset: const Duration(milliseconds: 18),
    timingBias: const Duration(milliseconds: -2),
    coachingSummary: const ['practice.coach.late'],
    skillTags: const ['smoke'],
    highestStableTempoBpm: 100.0,
  );
}

extension on PracticeHistoryEntry {
  PracticeHistoryEntry copyWith({
    String? id,
    PracticeMetricSnapshot? finalMetricSnapshot,
    int? attemptsCount,
    Duration? activeDuration,
    int? totalTargets,
    int? resolvedTargets,
  }) {
    return PracticeHistoryEntry(
      id: id ?? this.id,
      modeCode: modeCode,
      sourceCode: sourceCode,
      createdAt: createdAt,
      definitionId: definitionId,
      displayTitle: displayTitle,
      finishReasonCode: finishReasonCode,
      activeDuration: activeDuration ?? this.activeDuration,
      pausedDuration: pausedDuration,
      attemptsCount: attemptsCount ?? this.attemptsCount,
      finalMetricSnapshot: finalMetricSnapshot ?? this.finalMetricSnapshot,
      totalTargets: totalTargets ?? this.totalTargets,
      resolvedTargets: resolvedTargets ?? this.resolvedTargets,
      scorePoints: scorePoints,
      maxCombo: maxCombo,
      meanAbsoluteOffset: meanAbsoluteOffset,
      timingBias: timingBias,
      coachingSummary: coachingSummary,
      skillTags: skillTags,
      highestStableTempoBpm: highestStableTempoBpm,
      detailAttempts: detailAttempts,
    );
  }
}
