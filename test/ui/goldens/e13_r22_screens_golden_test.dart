// Golden snapshots of the E13-R22 Practice result / history / Speed Builder
// screens, at a compact portrait phone (412×915) and the same frame at
// textScaler 2.0 — the two frames the round brief §7/A9 requires. Pattern
// and sizing follow the merged
// `test/ui/goldens/e13_r21_screens_golden_test.dart` precedent: `AppTheme`
// (the app's actual runtime theme). §0.0/E15-R04: all three screens here
// (practice result/history, Speed Builder) now read
// `Theme.of(context).extension<SsColorScheme/SsTypography>()!` (migrated in
// this round) — `SsDarkTheme.data()` layers exactly those two extensions on
// top of the SAME `AppTheme.dark()` base (colorScheme/textTheme untouched),
// so this stops the null-check crash without changing rendered pixels for
// anything that doesn't read the new extensions.
//
// Recorded on x86_64 (ADR 0426, §0.0/R9) via `tools/golden-x86.sh record`
// — NOT `flutter test --update-goldens` on this (aarch64) box.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/themes/ss_dark_theme.dart';
import 'package:strumsight/core/storage/storage_keys.dart';
import 'package:strumsight/features/practice/data/practice_history_serializer.dart';
import 'package:strumsight/features/practice/domain/model/practice_attempt_result.dart';
import 'package:strumsight/features/practice/domain/model/practice_history_entry.dart';
import 'package:strumsight/features/practice/domain/model/practice_metric_snapshot.dart';
import 'package:strumsight/features/practice/domain/model/practice_metrics.dart';
import 'package:strumsight/features/practice/domain/model/practice_mode.dart';
import 'package:strumsight/features/practice/domain/model/practice_source.dart';
import 'package:strumsight/features/practice/domain/model/practice_verdict.dart';
import 'package:strumsight/features/practice/domain/model/speed_builder_policy.dart';
import 'package:strumsight/features/practice/domain/model/speed_builder_state.dart';
import 'package:strumsight/features/practice/domain/model/tempo.dart';
import 'package:strumsight/features/practice/domain/service/speed_builder_engine.dart';
import 'package:strumsight/features/practice/presentation/screens/practice_history_screen.dart';
import 'package:strumsight/features/practice/presentation/screens/practice_result_screen.dart';
import 'package:strumsight/features/practice/presentation/screens/speed_builder_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../support/preference_store.dart';

const _compactPortrait = Size(412, 915);

Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  List<Override>? overrides,
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = _compactPortrait;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      // Callers that need a seeded key/value store pass their OWN full
      // override list (it already includes a `keyValueStoreProvider`
      // override) — Riverpod 3 throws on a provider overridden twice in
      // the same container, so the default is used only when the caller
      // supplies none.
      overrides: overrides ?? preferenceOverrides(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: SsDarkTheme.data(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _expectGolden(WidgetTester tester, String name) => expectLater(
  find.byType(MaterialApp),
  matchesGoldenFile('goldens/$name.png'),
);

PracticeHistoryEntry _resultFixture() {
  return PracticeHistoryEntry(
    id: 'golden.result.v1',
    modeCode: PracticeMode.chordProgression.code,
    sourceCode: PracticeSource.builtin.code,
    createdAt: DateTime(2026, 8, 1, 12, 0),
    definitionId: 'golden.result',
    displayTitle: 'G to D changes',
    finishReasonCode: 'completedAllTargets',
    activeDuration: const Duration(minutes: 1, seconds: 20),
    pausedDuration: Duration.zero,
    attemptsCount: 3,
    finalMetricSnapshot: const PracticeMetricSnapshot(
      completion: PracticeMetricDimensionAvailable(0.92),
      rhythm: PracticeMetricDimensionAvailable(0.88),
      direction: PracticeMetricDimensionAvailable(0.9),
      chord: PracticeMetricDimensionAvailable(0.85),
      overall: PracticeMetricDimensionAvailable(0.9),
    ),
    totalTargets: 20,
    resolvedTargets: 19,
    scorePoints: 900,
    maxCombo: 18,
    meanAbsoluteOffset: const Duration(milliseconds: 15),
    timingBias: const Duration(milliseconds: -3),
    coachingSummary: const ['practice.coach.positive_reinforcement'],
    skillTags: const ['chord.change.g_to_d'],
    highestStableTempoBpm: 110.0,
  );
}

Map<String, Object> _historySeed() {
  final entries = [
    PracticeHistoryEntry(
      id: 'golden.history.1',
      modeCode: PracticeMode.strumPattern.code,
      sourceCode: PracticeSource.builtin.code,
      createdAt: DateTime(2026, 7, 30, 9, 0),
      definitionId: 'golden.history.1',
      displayTitle: 'Quarter downstrokes',
      finishReasonCode: 'completedAllTargets',
      activeDuration: const Duration(seconds: 45),
      pausedDuration: Duration.zero,
      attemptsCount: 1,
      finalMetricSnapshot: const PracticeMetricSnapshot(
        completion: PracticeMetricDimensionAvailable(0.95),
        rhythm: PracticeMetricDimensionAvailable(0.9),
        direction: PracticeMetricDimensionAvailable(0.88),
        chord: PracticeMetricDimensionNotApplicable(),
        overall: PracticeMetricDimensionAvailable(0.91),
      ),
      totalTargets: 16,
      resolvedTargets: 16,
      scorePoints: 850,
      maxCombo: 16,
      meanAbsoluteOffset: const Duration(milliseconds: 14),
      timingBias: Duration.zero,
      coachingSummary: const [],
      skillTags: const ['rhythm.quarter_notes'],
      highestStableTempoBpm: null,
    ),
    PracticeHistoryEntry(
      id: 'golden.history.2',
      modeCode: PracticeMode.chordChanges.code,
      sourceCode: PracticeSource.builtin.code,
      createdAt: DateTime(2026, 7, 29, 18, 30),
      definitionId: 'golden.history.2',
      displayTitle: 'G to D changes',
      finishReasonCode: 'interrupted',
      activeDuration: const Duration(seconds: 30),
      pausedDuration: Duration.zero,
      attemptsCount: 1,
      finalMetricSnapshot: const PracticeMetricSnapshot(
        completion: PracticeMetricDimensionAvailable(0.4),
        rhythm: PracticeMetricDimensionAvailable(0.5),
        direction: PracticeMetricDimensionNotApplicable(),
        chord: PracticeMetricDimensionAvailable(0.45),
        overall: PracticeMetricDimensionAvailable(0.45),
      ),
      totalTargets: 20,
      resolvedTargets: 8,
      scorePoints: 300,
      maxCombo: 4,
      meanAbsoluteOffset: const Duration(milliseconds: 30),
      timingBias: const Duration(milliseconds: 10),
      coachingSummary: const [],
      skillTags: const ['chord.change.g_to_d'],
      highestStableTempoBpm: null,
    ),
  ];
  return <String, Object>{
    StorageKeys.practiceHistoryV2: jsonEncode(<String, Object?>{
      'schemaVersion': 1,
      'items': [
        for (final entry in entries)
          const PracticeHistorySerializer().toJson(entry),
      ],
    }),
  };
}

SpeedBuilderState _speedBuilderActiveFixture() {
  const policy = SpeedBuilderPolicy(
    startBpm: Tempo(100),
    targetBpm: Tempo(160),
    stepBpm: 10,
  );
  const engine = SpeedBuilderEngine();
  var state = SpeedBuilderState.initial(policy);
  state = engine.record(state, _passAttempt(0, 100));
  state = engine.record(state, _passAttempt(1, 100));
  state = engine.record(state, _passAttempt(2, 110));
  return state;
}

PracticeAttemptResult _passAttempt(int index, double bpm) =>
    PracticeAttemptResult(
      index: index,
      tempo: Tempo(bpm),
      metrics: const PracticeMetrics(
        completion: MetricAvailable(0.98),
        rhythm: MetricAvailable(0.9),
        direction: MetricNotApplicable(),
        chord: MetricNotApplicable(),
        overall: MetricAvailable(0.9),
        totalTargets: 8,
        resolvedTargets: 8,
        maxCombo: 8,
        scorePoints: 800,
        meanAbsoluteOffset: Duration(milliseconds: 20),
        timingBias: Duration.zero,
      ),
      verdicts: const <PracticeVerdict>[],
      outcome: PracticeAttemptOutcome.passed,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final textScale in [1.0, 2.0]) {
    final suffix = textScale == 1.0 ? 'compact' : 'compact_scale2';

    testWidgets('practice result — $suffix', (tester) async {
      await _pump(
        tester,
        PracticeResultScreen(entry: _resultFixture()),
        textScale: textScale,
      );
      await _expectGolden(tester, 'e13_r22_practice_result_$suffix');
    });

    testWidgets('practice history — $suffix', (tester) async {
      await _pump(
        tester,
        const PracticeHistoryScreen(),
        overrides: [
          preferenceStoreOverride(InMemoryKeyValueStore(_historySeed())),
        ],
        textScale: textScale,
      );
      await _expectGolden(tester, 'e13_r22_practice_history_$suffix');
    });

    testWidgets('speed builder — active — $suffix', (tester) async {
      const policy = SpeedBuilderPolicy(
        startBpm: Tempo(100),
        targetBpm: Tempo(160),
        stepBpm: 10,
      );
      await _pump(
        tester,
        SpeedBuilderScreen(
          policy: policy,
          initialState: _speedBuilderActiveFixture(),
        ),
        textScale: textScale,
      );
      await _expectGolden(tester, 'e13_r22_speed_builder_$suffix');
    });
  }
}
