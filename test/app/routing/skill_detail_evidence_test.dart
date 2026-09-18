// A2b — Progress V2 evidence links must actually OPEN the referenced
// session. `skill_detail_screen.dart` hands `AppRoutes.profileLibrarySession`
// to the router callback, and that route's redirect requires a `LibraryItem`
// in `state.extra`; pushing it with only the `:sessionId` substituted made
// every evidence tap bounce straight back to the library list. The router
// now resolves the practice-history entry behind the evidence sessionId and
// pushes it as the `extra` the route contract asks for.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/app/routing/app_router.dart';
import 'package:strumsight/core/design_system/themes/ss_light_theme.dart';
import 'package:strumsight/features/library_v2/domain/library_item.dart';
import 'package:strumsight/features/library_v2/screens/library_item_detail_screen.dart';
import 'package:strumsight/features/onboarding/onboarding_provider.dart';
import 'package:strumsight/features/practice/public.dart';
import 'package:strumsight/features/progress_v2/public.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../support/preference_store.dart';

PracticeMetricSnapshot _chordSnapshot(double value) => PracticeMetricSnapshot(
  completion: const PracticeMetricDimensionNotApplicable(),
  rhythm: const PracticeMetricDimensionNotApplicable(),
  direction: const PracticeMetricDimensionNotApplicable(),
  chord: PracticeMetricDimension.available(value),
  overall: PracticeMetricDimension.available(value),
);

PracticeHistoryEntry _chordSession(
  String id,
  String displayTitle,
  DateTime createdAt,
) => PracticeHistoryEntry(
  id: id,
  modeCode: 'practice.mode.strumPattern',
  sourceCode: 'builtin',
  createdAt: createdAt,
  definitionId: 'builtin.quarterDownstrokes.v1',
  displayTitle: displayTitle,
  finishReasonCode: PracticeFinishReason.completedAllTargets.code,
  activeDuration: const Duration(seconds: 30),
  pausedDuration: Duration.zero,
  attemptsCount: 1,
  finalMetricSnapshot: _chordSnapshot(0.9),
  totalTargets: 4,
  resolvedTargets: 4,
  scorePoints: 100,
  maxCombo: 4,
  meanAbsoluteOffset: Duration.zero,
  timingBias: Duration.zero,
  coachingSummary: const <String>[],
  skillTags: const <String>[],
);

/// Three qualifying sessions clear `mastery_chord_transition_v1`'s
/// `minEvidenceSessions: 3`, so the skill detail renders a real evidence
/// list to tap.
List<PracticeHistoryEntry> _threeQualifyingChordSessions() => [
  _chordSession('chord-1', 'Chord run one', DateTime.utc(2026, 8, 1)),
  _chordSession('chord-2', 'Chord run two', DateTime.utc(2026, 8, 2)),
  _chordSession('chord-3', 'Chord run three', DateTime.utc(2026, 8, 3)),
];

Future<GoRouter> _pumpRouterTo(
  WidgetTester tester,
  String path, {
  List<Override> extraOverrides = const [],
}) async {
  final container = ProviderContainer(
    overrides: [
      ...preferenceOverrides(),
      ...extraOverrides,
      onboardingSeenProvider.overrideWith(() => OnboardingController(true)),
      appConfigProvider.overrideWithValue(
        AppConfig(
          environment: AppEnvironment.development,
          apiBaseUrl: AppConfig.devApiBaseUrl,
          flags: const FeatureFlags(
            accountEnabled: false,
            diagnosticsEnabled: false,
            labModeAvailable: false,
            adaptiveShellEnabled: true,
          ),
          diagnosticsToken: AppConfig.devDiagnosticsToken,
          buildMode: 'test',
          appVersion: 'test',
        ),
      ),
    ],
  );
  addTearDown(container.dispose);

  final router = container.read(routerProvider);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: SsLightTheme.data(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();

  router.go(path);
  await tester.pumpAndSettle();
  return router;
}

void main() {
  testWidgets(
    'tapping an evidence row opens that session in the unified library '
    'detail, instead of bouncing back to the library list',
    (tester) async {
      final router = await _pumpRouterTo(
        tester,
        AppRoutes.profileProgressSkill.replaceFirst(
          ':skillId',
          'chordTransition',
        ),
        extraOverrides: [
          progressPracticeHistoryProvider.overrideWithValue(
            _threeQualifyingChordSessions(),
          ),
        ],
      );

      expect(find.byType(SkillDetailScreen), findsOneWidget);

      final row = find.byKey(const ValueKey('event-list-row-chord-1'));
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      await tester.tap(row);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(router.state.uri.path, '/profile/library/session/chord-1');
      expect(find.byType(LibraryItemDetailScreen), findsOneWidget);

      final detail = tester.widget<LibraryItemDetailScreen>(
        find.byType(LibraryItemDetailScreen),
      );
      final item = detail.item;
      expect(item, isA<PracticeLibraryItem>());
      expect(item.id, 'chord-1');
      expect((item as PracticeLibraryItem).title, 'Chord run one');
      expect(item.createdAt, DateTime.utc(2026, 8, 1));
    },
  );

  testWidgets(
    'the skill detail stays on the stack, so the evidence detail can be '
    'popped back to it',
    (tester) async {
      final router = await _pumpRouterTo(
        tester,
        AppRoutes.profileProgressSkill.replaceFirst(
          ':skillId',
          'chordTransition',
        ),
        extraOverrides: [
          progressPracticeHistoryProvider.overrideWithValue(
            _threeQualifyingChordSessions(),
          ),
        ],
      );

      final row = find.byKey(const ValueKey('event-list-row-chord-2'));
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      await tester.tap(row);
      await tester.pumpAndSettle();

      expect(router.state.uri.path, '/profile/library/session/chord-2');
      expect(router.canPop(), isTrue);

      router.pop();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(SkillDetailScreen), findsOneWidget);
    },
  );
}
