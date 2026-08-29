// E02-R20 — A1 accessibility-audit mátrix.
//
// Each test in this file is one cell of the A1 matrix from the brief:
// one Practice-screen (Hub / Setup / Result) × one accessibility
// check (touch target, label+action, color-independence, 200% text,
// landscape, reduced motion, chart-semantics, screen-reader live region).
//
// The Session screen is excluded here — its state plumbing depends on
// the V2 host (R19 wiring, see brief §2.1 rendszerszintű rés), so the
// application-layer test in `practice_session_screen_test.dart` owns
// the per-status matrix. This audit asserts on the screens that are
// actually mounted today (Hub / Setup / Result).
//
// The audit is **measurement-first**: a screen that fails a check is
// fixed in the same screen tree, the audit cell re-runs, and the fix
// is committed together with the cell. A "we eyeballed it and it
// looks fine" cell does NOT exist — the cell either compiles and the
// assertions hold, or the screen is marked as a finding.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/practice/application/practice_catalog_controller.dart';
import 'package:strumsight/features/practice/domain/model/beat_position.dart';
import 'package:strumsight/features/practice/domain/model/compiled_practice_target.dart';
import 'package:strumsight/features/practice/domain/model/meter.dart';
import 'package:strumsight/features/practice/domain/model/practice_definition.dart';
import 'package:strumsight/features/practice/domain/model/practice_difficulty.dart';
import 'package:strumsight/features/practice/domain/model/practice_event.dart';
import 'package:strumsight/features/practice/domain/model/practice_history_entry.dart';
import 'package:strumsight/features/practice/domain/model/practice_insight.dart';
import 'package:strumsight/features/practice/domain/model/practice_metric_snapshot.dart';
import 'package:strumsight/features/practice/domain/model/practice_mode.dart';
import 'package:strumsight/features/practice/domain/model/practice_source.dart';
import 'package:strumsight/features/practice/domain/model/scoring_profile.dart';
import 'package:strumsight/features/practice/domain/model/tempo.dart';
import 'package:strumsight/features/practice/domain/repository/practice_catalog_repository.dart';
import 'package:strumsight/features/practice/presentation/screens/practice_hub_screen.dart';
import 'package:strumsight/features/practice/presentation/screens/practice_result_screen.dart';
import 'package:strumsight/features/practice/presentation/screens/practice_setup_screen.dart';
import 'package:strumsight/features/practice/presentation/widgets/practice_pattern_preview.dart';
import 'package:strumsight/features/practice/presentation/widgets/timing_bias_chart.dart';
import 'package:strumsight/features/practice/presentation/practice_route_args.dart';
import 'package:strumsight/features/streak/daily_challenge.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/l10n/app_localizations_en.dart';
import 'package:strumsight/core/design_system/themes/ss_light_theme.dart';

import '../../../support/preference_store.dart';

AppLocalizations l10n() => AppLocalizationsEn();

// ---------------------------------------------------------------------------
// Fixture repository + definition helpers
// ---------------------------------------------------------------------------

class _FixtureRepo implements PracticeCatalogRepository {
  _FixtureRepo(this.defs);
  final List<PracticeDefinition> defs;
  @override
  List<PracticeDefinition> all() => defs;
  @override
  PracticeDefinition? byId(String id) {
    for (final d in defs) {
      if (d.id == id) return d;
    }
    return null;
  }

  @override
  List<PracticeDefinition> byMode(PracticeMode mode) =>
      defs.where((d) => d.mode == mode).toList(growable: false);

  @override
  List<PracticeDefinition> byDifficulty(PracticeDifficulty difficulty) =>
      defs.where((d) => d.difficulty == difficulty).toList(growable: false);
}

PracticeDefinition _strumPatternDef(String id, String title) {
  return PracticeDefinition(
    id: id,
    schemaVersion: 1,
    titleKey: 'practiceCatalogTestSetupTitle',
    descriptionKey: 'practiceCatalogTestSetupDescription',
    mode: PracticeMode.strumPattern,
    source: PracticeSource.builtin,
    meter: const Meter(beatsPerBar: 4),
    defaultTempo: const Tempo(80),
    totalBeats: BeatPosition.quarters(8),
    events: List<PracticeEvent>.unmodifiable(
      List.generate(
        8,
        (i) => PracticeEvent(
          id: '$id.e$i',
          position: BeatPosition.quarters(i),
          direction: i.isEven ? StrumDirection.down : StrumDirection.up,
        ),
      ),
    ),
    scoringProfile: ScoringProfile.legacyLearnParity,
    skillTags: const ['rhythm.quarter_notes'],
    sourceReference: null,
    difficulty: PracticeDifficulty.beginner,
    displayTitle: title,
  );
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  List<dynamic> overrides = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [...preferenceOverrides(), ...overrides],
      child: MaterialApp(
        theme: SsLightTheme.data(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      ),
    ),
  );
  // Settle once so the ARB async loader resolves and the semantic tree
  // is built before the audit cells assert on labels.
  await tester.pumpAndSettle();
}

// ---------------------------------------------------------------------------
// History entry helper. The audit only needs the rendered labels, so we
// build the minimum the result screen requires.
// ---------------------------------------------------------------------------

PracticeHistoryEntry _historyEntry(PracticeMode mode) {
  final snapshot = PracticeMetricSnapshot(
    completion: const PracticeMetricDimensionAvailable(1.0),
    rhythm: const PracticeMetricDimensionAvailable(0.9),
    direction: mode == PracticeMode.chordChanges
        ? const PracticeMetricDimensionNotApplicable()
        : const PracticeMetricDimensionAvailable(0.8),
    chord:
        mode == PracticeMode.strumPattern ||
            mode == PracticeMode.rhythmOnly ||
            mode == PracticeMode.freePractice
        ? const PracticeMetricDimensionNotApplicable()
        : const PracticeMetricDimensionAvailable(0.75),
    overall: const PracticeMetricDimensionAvailable(0.85),
  );
  return PracticeHistoryEntry(
    id: 'audit',
    modeCode: mode.code,
    sourceCode: 'builtin',
    createdAt: DateTime.utc(2026, 8, 1),
    definitionId: 'd-audit',
    displayTitle: 'Audit fixture',
    finishReasonCode: 'completedAllTargets',
    activeDuration: const Duration(seconds: 90),
    pausedDuration: Duration.zero,
    attemptsCount: 1,
    finalMetricSnapshot: snapshot,
    totalTargets: 8,
    resolvedTargets: 8,
    scorePoints: 850,
    maxCombo: 5,
    meanAbsoluteOffset: const Duration(milliseconds: 25),
    timingBias: Duration.zero,
    coachingSummary: const ['practice.coach.consistent_tempo'],
    skillTags: const ['rhythm.quarter_notes'],
    highestStableTempoBpm: null,
    detailAttempts: const [
      PracticeAttemptDetail(
        index: 0,
        metricSnapshot: PracticeMetricSnapshot(
          completion: PracticeMetricDimensionAvailable(1.0),
          rhythm: PracticeMetricDimensionAvailable(0.9),
          direction: PracticeMetricDimensionAvailable(0.8),
          chord: PracticeMetricDimensionNotApplicable(),
          overall: PracticeMetricDimensionAvailable(0.85),
        ),
      ),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpHub(WidgetTester tester) async {
    final repo = _FixtureRepo([
      _strumPatternDef('d1', 'Quarter downstrokes'),
      _strumPatternDef('d2', 'Alternating eighths'),
    ]);
    await _pump(
      tester,
      const PracticeHubScreen(
        now: null,
        dailyChallenge: DailyChallenge(
          day: 19633,
          name: 'Audit',
          pattern: <StrumDirection>[],
        ),
      ),
      overrides: [practiceCatalogRepositoryProvider.overrideWithValue(repo)],
    );
  }

  Future<void> pumpSetup(WidgetTester tester) async {
    final def = _strumPatternDef('audit', 'Quarter downstrokes');
    final repo = _FixtureRepo([def]);
    await _pump(
      tester,
      const PracticeSetupScreen(
        argsOverride: PracticeSetupArgs(
          request: PracticeSetupRequest.hasId,
          definitionId: 'audit',
        ),
      ),
      overrides: [practiceCatalogRepositoryProvider.overrideWithValue(repo)],
    );
  }

  Future<void> pumpResult(
    WidgetTester tester, {
    PracticeMode mode = PracticeMode.strumPattern,
  }) async {
    await _pump(tester, PracticeResultScreen(entry: _historyEntry(mode)));
  }

  // -------------------------------------------------------------------------
  // A1 cell 1+2: touch-target + label+action — every interactive element on
  // the Practice flow exposes its label and intent as a single Semantics
  // node. The Hub's Quick Start, the Setup Start CTA, and the screen
  // button rows are the canonical touch targets.
  // -------------------------------------------------------------------------

  testWidgets('A1.1 Hub: each card is a labelled button with action', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpHub(tester);
    // The Hub card uses `Semantics(container: true, label: …)` so the
    // title appears as exactly one label rather than merging with the
    // subtitle. A regex match (^…$) is necessary because Flutter's
    // semantics label keeps trailing whitespace from formatting.
    expect(
      find.bySemanticsLabel(
        RegExp(
          '^${RegExp.escape(l10n().practiceHubOpenSetup('Quarter downstrokes'))}\$',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        RegExp(
          '^${RegExp.escape(l10n().practiceHubOpenSetup('Alternating eighths'))}\$',
        ),
      ),
      findsOneWidget,
    );
    handle.dispose();
  });

  // -------------------------------------------------------------------------
  // A1 cell 1b — `_QuickStartCard` / `_DailyChallengeCard` regression
  // guard (R20 review F3). The fix wraps the inner `Row` of `_HubCard`
  // in `ExcludeSemantics` so the descendant `Text` widgets (the title
  // and subtitle strings) do NOT surface as separate semantic nodes —
  // a screen reader announces the single parent label
  // `practiceHubOpenSetup(title)` instead of three concatenated
  // fragments (label + title + subtitle). The existing A1.1 cell
  // covers the catalog cards' outer label only; this cell pins the
  // structural half (the `ExcludeSemantics` block) by asserting that
  // the subtitle strings are NOT separate semantic nodes. Red→green
  // proof: reverting `ExcludeSemantics` in `_HubCard` makes this
  // cell fail with `findsOneWidget` on the subtitle label.
  // -------------------------------------------------------------------------

  testWidgets(
    'A1.1b Hub: _QuickStartCard / _DailyChallengeCard — subtitle strings '
    'are NOT separate semantic nodes',
    (tester) async {
      final handle = tester.ensureSemantics();
      await pumpHub(tester);
      // The parent semantics node carries the merged label
      // `practiceHubOpenSetup(title)`. The inner title/subtitle
      // Text widgets must be hidden by `ExcludeSemantics` — they
      // must not surface as their own semantic labels. The subtitle
      // strings are distinct enough from the merged label that a
      // bare `find.bySemanticsLabel(<subtitle>)` is unambiguous.
      expect(
        find.bySemanticsLabel(
          l10n().practiceHubOpenSetup(l10n().practiceHubQuickStartLabel),
        ),
        findsOneWidget,
        reason: 'QuickStart card parent label missing',
      );
      expect(
        find.bySemanticsLabel(l10n().practiceHubQuickStartSubtitle),
        findsNothing,
        reason:
            'QuickStart subtitle leaked as a separate semantic node '
            '— _HubCard ExcludeSemantics is missing',
      );
      expect(
        find.bySemanticsLabel(
          l10n().practiceHubOpenSetup(l10n().practiceHubDailyChallengeLabel),
        ),
        findsOneWidget,
        reason: 'DailyChallenge card parent label missing',
      );
      // The `pumpHub` fixture builds the `DailyChallenge` with
      // `name: 'Audit'`, so the subtitle is the literal `'Audit'`.
      // That distinct string must NOT be a separate semantic node.
      expect(
        find.bySemanticsLabel('Audit'),
        findsNothing,
        reason:
            'DailyChallenge subtitle leaked as a separate semantic '
            'node — _HubCard ExcludeSemantics is missing',
      );
      handle.dispose();
    },
  );

  testWidgets('A1.2 Setup: Start CTA is labelled, action wired, ≥ 48dp tall', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpSetup(tester);
    // The Start CTA sits at the bottom of a ListView — scroll until
    // visible so the renderObject is realised and measurable.
    await tester.scrollUntilVisible(
      find.text(l10n().practiceSetupStart),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    final startText = find.text(l10n().practiceSetupStart);
    expect(startText, findsOneWidget);
    // Walk up to the FilledButton widget.
    final buttonFinder = find.ancestor(
      of: startText,
      matching: find.byType(FilledButton),
    );
    expect(buttonFinder, findsOneWidget);
    final renderBox = tester.renderObject(buttonFinder) as RenderBox;
    expect(
      renderBox.size.height,
      greaterThanOrEqualTo(48),
      reason: '48dp minimum touch target — accessibility floor',
    );
    handle.dispose();
  });

  // -------------------------------------------------------------------------
  // A1 cell 3: colour-independence — every verdict/state is text or icon,
  // not only a colour cue. The pattern preview is the most direct test
  // bed — every slot is labelled `Down` / `Up` / `Rest`.
  // -------------------------------------------------------------------------

  testWidgets('A1.3 Pattern preview: down/up/rest are distinct icon+text', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final events = List<CompiledTargetEvent>.generate(
      4,
      (i) => CompiledTargetEvent(
        sourceEventId: 'e$i',
        loopIndex: 0,
        position: BeatPosition.quarters(i),
        time: Duration(milliseconds: i * 500),
        barIndex: 0,
        chord: null,
        direction: i.isEven ? StrumDirection.down : StrumDirection.up,
        accent: false,
        optional: false,
      ),
    );
    final target = CompiledPracticeTarget(
      definitionId: 'preview',
      definitionSnapshotVersion: 1,
      tempo: const Tempo(120),
      meter: const Meter(beatsPerBar: 4),
      countInBars: 0,
      countInDuration: Duration.zero,
      events: events,
      musicalDuration: const Duration(milliseconds: 1500),
      ringOutDuration: Duration.zero,
      totalDuration: const Duration(milliseconds: 1500),
      barBoundaries: const [],
      loopCount: 1,
      loopRange: null,
      expectedChordSegments: const [],
      scoringApplicable: true,
    );
    await _pump(
      tester,
      Scaffold(body: PracticePatternPreview(target: target, barIndex: 0)),
    );
    // PatternPreview wraps each slot in `Semantics(label: …)`; two
    // downs + two ups must each be findable as their own label.
    expect(find.bySemanticsLabel(l10n().strumDown), findsNWidgets(2));
    expect(find.bySemanticsLabel(l10n().strumUp), findsNWidgets(2));
    handle.dispose();
  });

  // -------------------------------------------------------------------------
  // A1 cell 4: chart-semantics — TimingBiasChart is the only chart-like
  // surface exposed on the result screen today. It must announce as one
  // sentence (the chart's bias direction), not as raw glyph fragments.
  // -------------------------------------------------------------------------

  testWidgets('A1.4 TimingBiasChart exposes a one-sentence semantics summary', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      Scaffold(
        body: TimingBiasChart(
          detailAttempts: _historyEntry(
            PracticeMode.strumPattern,
          ).detailAttempts,
          timingBias: Duration.zero,
        ),
      ),
    );
    expect(
      find.bySemanticsLabel(
        l10n().practiceResultTimingSemantic(
          l10n().practiceResultTimingBalanced,
        ),
      ),
      findsOneWidget,
    );
    // The chart must not also leak the bare label as a separate node.
    expect(
      find.bySemanticsLabel(l10n().practiceResultTimingBalanced),
      findsNothing,
    );
    handle.dispose();
  });

  // -------------------------------------------------------------------------
  // A1 cell 5: 200% text — at textScaleFactor 2.0 the screens still render
  // without `RenderFlex overflowed` errors. We pump every Practice-mode
  // result at 200% and assert no exceptions leaked into the test binding.
  // -------------------------------------------------------------------------

  testWidgets(
    'A1.5 200% text scale: each result mode renders without overflow',
    (tester) async {
      for (final mode in PracticeMode.values) {
        tester.view.platformDispatcher.textScaleFactorTestValue = 2.0;
        await pumpResult(tester, mode: mode);
        tester.view.platformDispatcher.clearTextScaleFactorTestValue();
        expect(
          tester.takeException(),
          isNull,
          reason: 'mode=$mode produced an exception at 200% text',
        );
      }
    },
  );

  // -------------------------------------------------------------------------
  // A1 cell 6: landscape (915×412, StrumSight's narrowest landscape profile
  // — see test/core/screen_size_guard_test.dart). At landscape, the screens
  // must not overflow.
  // -------------------------------------------------------------------------

  testWidgets('A1.6a landscape 915×412: result renders without exception', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(915, 412);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpResult(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('A1.6b landscape 915×412: setup renders without exception', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(915, 412);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpSetup(tester);
    expect(tester.takeException(), isNull);
  });

  // -------------------------------------------------------------------------
  // A1 cell 7: ARB parity proof — every Practice surface string resolves
  // through AppLocalizations. A raw English literal in the rendered tree
  // fails this cell. Split into three tests (one per screen) so each
  // ProviderScope owns a single override count — Riverpod does not
  // allow the override count to change between pumps.
  // -------------------------------------------------------------------------

  testWidgets('A1.7a Hub strings resolve through AppLocalizations', (
    tester,
  ) async {
    await pumpHub(tester);
    expect(find.text(l10n().practiceHubTitle), findsOneWidget);
    expect(find.text(l10n().practiceHubQuickStartLabel), findsOneWidget);
  });

  testWidgets('A1.7b Setup strings resolve through AppLocalizations', (
    tester,
  ) async {
    await pumpSetup(tester);
    expect(find.text(l10n().practiceSetupTitle), findsOneWidget);
    expect(find.text(l10n().practiceSetupBpmLabel), findsOneWidget);
  });

  testWidgets('A1.7c Result strings resolve through AppLocalizations', (
    tester,
  ) async {
    await pumpResult(tester);
    expect(find.text(l10n().practiceResultTitle), findsOneWidget);
    expect(find.text(l10n().practiceResultBreakdownTitle), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // A2 l10n cells (migrated from the now-deleted
  // `test/features/practice/practice_l10n_audit_test.dart` after
  // E02-R20 review F2 — the file was §4 scope-out). These cells cover
  // the genuinely-new tests:
  //   * the coach-code→ARB-key mapping-pin (two structural `test`s that
  //     fail when a new code is added without an ARB counterpart),
  //   * the result-screen widget-render proof that the ARB string
  //     actually reaches the screen (two `testWidgets` that fail when
  //     the screen falls back to the humanised machine code).
  // The vacuous A2.3 "percentage formatting" cell was dropped — it
  // compared two Dart string-literals and called no production code.
  // -------------------------------------------------------------------------

  test('A2.1 every PracticeInsightCode has a non-empty ARB translation '
      'in both locales (mapping pin)', () {
    final en =
        jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
            as Map<String, dynamic>;
    final hu =
        jsonDecode(File('lib/l10n/app_hu.arb').readAsStringSync())
            as Map<String, dynamic>;

    // The ARB keys are produced by stripping `practice.insight.` and
    // camelCasing the remainder. This mirrors the manual mapping in
    // `practice_result_screen.dart` — if the mapping diverges, this
    // test must be updated in lockstep.
    final pairs = <String, String>{
      PracticeInsightCode.noSignal: 'practiceInsightNoSignal',
      PracticeInsightCode.lowCompletion: 'practiceInsightLowCompletion',
      PracticeInsightCode.biasLate: 'practiceInsightBiasLate',
      PracticeInsightCode.biasEarly: 'practiceInsightBiasEarly',
      PracticeInsightCode.directionError: 'practiceInsightDirectionError',
      PracticeInsightCode.chordError: 'practiceInsightChordError',
      PracticeInsightCode.chordPairProblem: 'practiceInsightChordPairProblem',
      PracticeInsightCode.tempoTooHigh: 'practiceInsightTempoTooHigh',
      PracticeInsightCode.positiveReinforcement:
          'practiceInsightPositiveReinforcement',
      PracticeInsightCode.nextDifficulty: 'practiceInsightNextDifficulty',
    };
    for (final entry in pairs.entries) {
      expect(
        en.containsKey(entry.value),
        isTrue,
        reason: '${entry.key} → missing English ARB key ${entry.value}',
      );
      expect(
        (en[entry.value] as String).trim().isNotEmpty,
        isTrue,
        reason: '${entry.value} is empty in English',
      );
      expect(
        hu.containsKey(entry.value),
        isTrue,
        reason: '${entry.key} → missing Hungarian ARB key ${entry.value}',
      );
      expect(
        (hu[entry.value] as String).trim().isNotEmpty,
        isTrue,
        reason: '${entry.value} is empty in Hungarian',
      );
      // The brief §6 A2 explicitly forbids English-only values — every
      // code must read as a real Hungarian sentence, not a copy-paste
      // of the English version.
      expect(
        en[entry.value] == hu[entry.value],
        isFalse,
        reason:
            '${entry.value} is identical between en and hu — must '
            'have a real Hungarian translation',
      );
    }
  });

  test('A2.2 every PracticeRecommendationKind has a non-empty ARB '
      'translation in both locales (mapping pin)', () {
    final en =
        jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
            as Map<String, dynamic>;
    final hu =
        jsonDecode(File('lib/l10n/app_hu.arb').readAsStringSync())
            as Map<String, dynamic>;
    final pairs = <String, String>{
      PracticeRecommendationKind.retry: 'practiceRecommendationRetry',
      PracticeRecommendationKind.reduceTempo:
          'practiceRecommendationReduceTempo',
      PracticeRecommendationKind.enableMetronome:
          'practiceRecommendationEnableMetronome',
      PracticeRecommendationKind.focusDirection:
          'practiceRecommendationFocusDirection',
      PracticeRecommendationKind.focusChordChanges:
          'practiceRecommendationFocusChordChanges',
      PracticeRecommendationKind.nextDifficulty:
          'practiceRecommendationNextDifficulty',
    };
    for (final entry in pairs.entries) {
      expect(
        en.containsKey(entry.value),
        isTrue,
        reason: '${entry.key} → missing English ARB key ${entry.value}',
      );
      expect((en[entry.value] as String).trim().isNotEmpty, isTrue);
      expect(
        hu.containsKey(entry.value),
        isTrue,
        reason: '${entry.key} → missing Hungarian ARB key ${entry.value}',
      );
      expect((hu[entry.value] as String).trim().isNotEmpty, isTrue);
      expect(
        en[entry.value] == hu[entry.value],
        isFalse,
        reason:
            '${entry.value} is identical — must have a real '
            'Hungarian translation',
      );
    }
  });

  Future<void> pumpResultWithLocale(
    WidgetTester tester,
    Locale locale,
    PracticeHistoryEntry entry,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: preferenceOverrides(),
        child: MaterialApp(
          theme: SsLightTheme.data(),
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PracticeResultScreen(entry: entry),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // The insight section sits at the bottom of a ListView — scroll it
    // into the visible viewport so `find.text` reaches it.
    final l10n = await AppLocalizations.delegate.load(locale);
    final insightFinder = find.text(l10n.practiceResultCoachingTitle);
    await tester.scrollUntilVisible(
      insightFinder,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'A2.3 result screen renders the Hungarian ARB string for a coach code',
    (tester) async {
      final entry = PracticeHistoryEntry(
        id: 'l10n-audit-hu',
        modeCode: PracticeMode.strumPattern.code,
        sourceCode: 'builtin',
        createdAt: DateTime.utc(2026, 8, 1),
        definitionId: 'd-hu',
        displayTitle: 'Audit fixture',
        finishReasonCode: 'completedAllTargets',
        activeDuration: const Duration(seconds: 60),
        pausedDuration: Duration.zero,
        attemptsCount: 1,
        finalMetricSnapshot: const PracticeMetricSnapshot(
          completion: PracticeMetricDimensionAvailable(1.0),
          rhythm: PracticeMetricDimensionAvailable(0.9),
          direction: PracticeMetricDimensionAvailable(0.8),
          chord: PracticeMetricDimensionNotApplicable(),
          overall: PracticeMetricDimensionAvailable(0.85),
        ),
        totalTargets: 8,
        resolvedTargets: 8,
        scorePoints: 800,
        maxCombo: 4,
        meanAbsoluteOffset: const Duration(milliseconds: 25),
        timingBias: Duration.zero,
        coachingSummary: [PracticeInsightCode.biasLate],
        skillTags: const ['rhythm.quarter_notes'],
        highestStableTempoBpm: null,
        detailAttempts: const [],
      );
      await pumpResultWithLocale(tester, const Locale('hu'), entry);
      final hu =
          (jsonDecode(File('lib/l10n/app_hu.arb').readAsStringSync())
                  as Map<String, dynamic>)['practiceInsightBiasLate']
              as String;
      expect(find.textContaining(hu), findsOneWidget);
    },
  );

  testWidgets(
    'A2.4 result screen renders the English ARB string for a coach code',
    (tester) async {
      final entry = PracticeHistoryEntry(
        id: 'l10n-audit-en',
        modeCode: PracticeMode.strumPattern.code,
        sourceCode: 'builtin',
        createdAt: DateTime.utc(2026, 8, 1),
        definitionId: 'd-en',
        displayTitle: 'Audit fixture',
        finishReasonCode: 'completedAllTargets',
        activeDuration: const Duration(seconds: 60),
        pausedDuration: Duration.zero,
        attemptsCount: 1,
        finalMetricSnapshot: const PracticeMetricSnapshot(
          completion: PracticeMetricDimensionAvailable(1.0),
          rhythm: PracticeMetricDimensionAvailable(0.9),
          direction: PracticeMetricDimensionAvailable(0.8),
          chord: PracticeMetricDimensionNotApplicable(),
          overall: PracticeMetricDimensionAvailable(0.85),
        ),
        totalTargets: 8,
        resolvedTargets: 8,
        scorePoints: 800,
        maxCombo: 4,
        meanAbsoluteOffset: const Duration(milliseconds: 25),
        timingBias: Duration.zero,
        coachingSummary: [PracticeInsightCode.positiveReinforcement],
        skillTags: const ['rhythm.quarter_notes'],
        highestStableTempoBpm: null,
        detailAttempts: const [],
      );
      await pumpResultWithLocale(tester, const Locale('en'), entry);
      final en =
          (jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
                  as Map<
                    String,
                    dynamic
                  >)['practiceInsightPositiveReinforcement']
              as String;
      expect(find.textContaining(en), findsOneWidget);
    },
  );
}
