// The result screen's Next action (learner-loop round): the ONE recommended
// next practice, named and explained, launched through Setup with its own
// definition id — with "Practice again" demoted to the secondary action
// when the recommendation is a different definition.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strumsight/core/design_system/themes/ss_light_theme.dart';
import 'package:strumsight/features/practice/domain/model/beat_position.dart';
import 'package:strumsight/features/practice/domain/model/meter.dart';
import 'package:strumsight/features/practice/domain/model/practice_definition.dart';
import 'package:strumsight/features/practice/domain/model/practice_history_entry.dart';
import 'package:strumsight/features/practice/domain/model/practice_metric_snapshot.dart';
import 'package:strumsight/features/practice/domain/model/practice_mode.dart';
import 'package:strumsight/features/practice/domain/model/practice_source.dart';
import 'package:strumsight/features/practice/domain/model/scoring_profile.dart';
import 'package:strumsight/features/practice/domain/model/tempo.dart';
import 'package:strumsight/features/practice/presentation/screens/practice_result_screen.dart';
import 'package:strumsight/features/practice/presentation/screens/practice_setup_screen.dart';
import 'package:strumsight/features/practice/public.dart'
    show practiceCatalogProvider, practiceHistoryV2ListProvider;
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/l10n/app_localizations_en.dart';

import '../../../support/preference_store.dart';

const _nextKey = ValueKey('practice-result-next-recommended');
const _againKey = ValueKey('practice-result-practice-again');
const _reasonKey = ValueKey('practice-result-next-reason');

PracticeDefinition _def(String id, String title) => PracticeDefinition(
  id: id,
  schemaVersion: 1,
  titleKey: 'practiceCatalogTestSingleTitle',
  descriptionKey: 'practiceCatalogTestSingleDescription',
  mode: PracticeMode.strumPattern,
  source: PracticeSource.builtin,
  meter: const Meter(beatsPerBar: 4),
  defaultTempo: const Tempo(80),
  totalBeats: const BeatPosition(4 * BeatPosition.ticksPerBeat),
  events: const [],
  scoringProfile: ScoringProfile.legacyLearnParity,
  skillTags: const ['test'],
  displayTitle: title,
);

PracticeHistoryEntry _entry({required int resolved}) => PracticeHistoryEntry(
  id: 'session-1',
  modeCode: PracticeMode.strumPattern.code,
  sourceCode: PracticeSource.builtin.code,
  createdAt: DateTime.utc(2026, 9, 1, 12),
  definitionId: 'first',
  displayTitle: 'First pattern',
  finishReasonCode: 'completedAllTargets',
  activeDuration: const Duration(seconds: 30),
  pausedDuration: Duration.zero,
  attemptsCount: 1,
  finalMetricSnapshot: const PracticeMetricSnapshot(
    completion: PracticeMetricDimensionAvailable(0.9),
    rhythm: PracticeMetricDimensionAvailable(0.85),
    direction: PracticeMetricDimensionAvailable(0.95),
    chord: PracticeMetricDimensionNotApplicable(),
    overall: PracticeMetricDimensionAvailable(0.9),
  ),
  totalTargets: 10,
  resolvedTargets: resolved,
  scorePoints: 0,
  maxCombo: 0,
  meanAbsoluteOffset: Duration.zero,
  timingBias: Duration.zero,
  coachingSummary: const [],
  skillTags: const [],
);

Future<void> _pump(WidgetTester tester, PracticeHistoryEntry entry) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...preferenceOverrides(),
        practiceCatalogProvider.overrideWithValue([
          _def('first', 'First pattern'),
          _def('second', 'Second pattern'),
        ]),
        // The session just finished is NOT in the persisted list yet — the
        // screen must still reason from it (`latest`).
        practiceHistoryV2ListProvider.overrideWith(
          (ref) async => const <PracticeHistoryEntry>[],
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
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final l10n = AppLocalizationsEn();

  testWidgets('a cleared session offers the NEXT definition as the primary '
      'action and demotes "Practice again"', (tester) async {
    await _pump(tester, _entry(resolved: 10));

    expect(
      find.text(l10n.practiceResultNextRecommendedCta('Second pattern')),
      findsOneWidget,
    );
    expect(
      tester.widget<Text>(find.byKey(_reasonKey)).data,
      l10n.practiceNextReasonAdvance,
    );
    expect(find.byKey(_againKey), findsOneWidget);
    expect(tester.widget(find.byKey(_againKey)), isA<OutlinedButton>());

    await tester.tap(find.byKey(_nextKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final setup = tester.widget<PracticeSetupScreen>(
      find.byType(PracticeSetupScreen),
    );
    expect(setup.argsOverride?.definitionId, 'second');
  });

  testWidgets('a weak session keeps the SAME definition as the one primary '
      'action, with the consolidation reason', (tester) async {
    await _pump(tester, _entry(resolved: 3));

    expect(find.byKey(_nextKey), findsNothing);
    expect(
      tester.widget<Text>(find.byKey(_reasonKey)).data,
      l10n.practiceNextReasonRepeat,
    );
    expect(tester.widget(find.byKey(_againKey)), isA<FilledButton>());

    await tester.tap(find.byKey(_againKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final setup = tester.widget<PracticeSetupScreen>(
      find.byType(PracticeSetupScreen),
    );
    expect(setup.argsOverride?.definitionId, 'first');
  });
}
