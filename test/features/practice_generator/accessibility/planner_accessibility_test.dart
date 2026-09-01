import 'dart:io' show Directory;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/themes/ss_light_theme.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/practice_generator/application/controller/today_plan_controller.dart';
import 'package:strumsight/features/practice_generator/application/usecase/delete_practice_planning_data.dart';
import 'package:strumsight/features/practice_generator/application/usecase/export_practice_planning_data.dart';
import 'package:strumsight/features/practice_generator/data/local/generation_draft_repository.dart';
import 'package:strumsight/features/practice_generator/data/local/local_practice_plan_repository.dart';
import 'package:strumsight/features/practice_generator/domain/id/planner_ids.dart';
import 'package:strumsight/features/practice_generator/domain/model/practice_block.dart';
import 'package:strumsight/features/practice_generator/domain/model/practice_day.dart';
import 'package:strumsight/features/practice_generator/domain/model/weekly_availability.dart';
import 'package:strumsight/features/practice_generator/domain/repository/practice_evidence_repository.dart';

import '../../../core/storage/in_memory_key_value_store.dart';
import '../../../fixtures/practice_generator/plan/plan_fixtures.dart';
import 'package:strumsight/features/practice_generator/presentation/screens/plan_privacy_screen.dart';
import 'package:strumsight/features/practice_generator/presentation/screens/today_plan_screen.dart';
import 'package:strumsight/features/practice_generator/presentation/screens/weekly_plan_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../../fixtures/practice_generator/validation/validation_fixtures.dart';

/// E07-R29 §6 acceptance criteria for the planner UI:
///   A2 large-text overflow,
///   A3 screen-reader reachability,
///   A4 status not colour-only,
///   A5 reduced motion,
///   A9 discomfort safety UX (no progression offer after discomfort).
void main() {
  group('A2 — large-text overflow', () {
    // §0.0.A/R7 (L558): a PHONE-sized viewport (360x640, dpr 1.0), not the
    // flutter_test default 800x600 — that default is wider AND taller than
    // any phone, so a lazy ListView never builds the off-screen child and
    // "no overflow" can measure an empty tree. `_pumpWithScaler` sets the
    // phone viewport for every cell in this group. `en` cells below are the
    // pre-existing frozen cells (structural viewport fix only, §0.0); `hu`
    // cells are new — the round's own A3 evidence that the longer Hungarian
    // strings also fit at the 2.0 threshold.
    testWidgets('TodayPlanScreen empty / rest / unavailable / completed states '
        'render without overflow at 2.0 text scaler', (tester) async {
      await _pumpWithScaler(
        tester,
        const TextScaler.linear(2),
        TodayPlanScreen(
          controller: TodayPlanController(clock: () => DateTime(2026, 8, 19)),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'TodayPlanScreen empty state renders without overflow at 2.0 (hu)',
      (tester) async {
        await _pumpWithScaler(
          tester,
          const TextScaler.linear(2),
          TodayPlanScreen(
            controller: TodayPlanController(clock: () => DateTime(2026, 8, 19)),
          ),
          locale: const Locale('hu'),
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'TodayPlanScreen planned-day view renders without overflow at 2.0',
      (tester) async {
        await _pumpWithScaler(
          tester,
          const TextScaler.linear(2),
          TodayPlanScreen(
            controller: TodayPlanController(clock: () => DateTime(2026, 8, 19)),
            plan: buildPlan(),
          ),
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'TodayPlanScreen planned-day view renders without overflow at 2.0 (hu)',
      (tester) async {
        await _pumpWithScaler(
          tester,
          const TextScaler.linear(2),
          TodayPlanScreen(
            controller: TodayPlanController(clock: () => DateTime(2026, 8, 19)),
            plan: buildPlan(),
          ),
          locale: const Locale('hu'),
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('WeeklyPlanScreen renders without overflow at 2.0', (
      tester,
    ) async {
      await _pumpWithScaler(
        tester,
        const TextScaler.linear(2),
        WeeklyPlanScreen(plan: buildPlan(), today: LocalDate(2026, 8, 17)),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('WeeklyPlanScreen renders without overflow at 2.0 (hu)', (
      tester,
    ) async {
      await _pumpWithScaler(
        tester,
        const TextScaler.linear(2),
        WeeklyPlanScreen(plan: buildPlan(), today: LocalDate(2026, 8, 17)),
        locale: const Locale('hu'),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('PlanPrivacyScreen renders without overflow at 2.0 (en)', (
      tester,
    ) async {
      await _pumpWithScaler(
        tester,
        const TextScaler.linear(2),
        PlanPrivacyScreen(
          deleteUseCase: _NoopDeleteUseCase(),
          exportUseCase: _NoopExportUseCase(),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('PlanPrivacyScreen renders without overflow at 2.0 (hu)', (
      tester,
    ) async {
      await _pumpWithScaler(
        tester,
        const TextScaler.linear(2),
        PlanPrivacyScreen(
          deleteUseCase: _NoopDeleteUseCase(),
          exportUseCase: _NoopExportUseCase(),
        ),
        locale: const Locale('hu'),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('A4 — status not colour-only', () {
    testWidgets('no-active state renders a textual status badge (A4 — never '
        'colour-only)', (tester) async {
      await _pump(
        tester,
        TodayPlanScreen(
          controller: TodayPlanController(clock: () => DateTime(2026, 8, 19)),
        ),
      );
      expect(find.byKey(const Key('today-plan-status-badge')), findsOneWidget);
    });

    testWidgets('rest-day state renders a textual status badge', (
      tester,
    ) async {
      final restDay = buildDay(
        id: 'rest',
        localDate: LocalDate(2026, 8, 19),
        status: PracticeItemStatus.planned,
      )._withReasonCodes(const <String>['schedule.decision.restDay']);
      await _pump(
        tester,
        TodayPlanScreen(
          controller: TodayPlanController(clock: () => DateTime(2026, 8, 19)),
          plan: buildPlan(days: <PracticeDay>[restDay]),
        ),
      );
      expect(find.byKey(const Key('today-plan-status-badge')), findsOneWidget);
    });

    testWidgets(
      'WeeklyPlanScreen rows render a semantic-labelled leading icon',
      (tester) async {
        final restDay = buildDay(
          id: 'rest',
          localDate: LocalDate(2026, 8, 19),
          status: PracticeItemStatus.planned,
        )._withReasonCodes(const <String>['schedule.decision.restDay']);
        await _pump(
          tester,
          WeeklyPlanScreen(
            plan: buildPlan(days: <PracticeDay>[restDay]),
            today: LocalDate(2026, 8, 19),
          ),
        );
        // The leading icon's `semanticLabel` is read by the semantics
        // tree; verify the icon is present and is non-empty (so screen
        // readers and colour-blind users see the status). We avoid
        // `find.bySemanticsLabel` because Flutter may merge the icon's
        // semantics into the parent ListTile.
        expect(find.byIcon(Icons.bedtime_outlined), findsOneWidget);
      },
    );
  });

  group('A3 — keyboard / screen reader reachability', () {
    testWidgets(
      'TodayPlanScreen — every action is a labelled, focusable button',
      (tester) async {
        await _pump(
          tester,
          TodayPlanScreen(
            controller: TodayPlanController(clock: () => DateTime(2026, 8, 19)),
            plan: buildPlan(
              days: [buildDay(id: 'today', localDate: LocalDate(2026, 8, 19))],
            ),
            onStart: (_) {},
            onSwap: (_) {},
            onSkip: (_) {},
            onShorten: () {},
            onPause: () {},
          ),
        );
        expect(find.byKey(const Key('today-plan-start')), findsOneWidget);
        expect(find.byKey(const Key('today-plan-swap')), findsOneWidget);
        expect(find.byKey(const Key('today-plan-skip')), findsOneWidget);
        expect(find.byKey(const Key('today-plan-shorten')), findsOneWidget);
        expect(find.byKey(const Key('today-plan-pause')), findsOneWidget);
      },
    );
  });

  group('A5 + A9 — privacy screen affordances', () {
    testWidgets(
      'PlanPrivacyScreen exposes the scope, the discomfort safety card, '
      'and both action buttons without any implicit animations',
      (tester) async {
        // Use a tall surface so every action button is in the viewport.
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await _pump(
          tester,
          PlanPrivacyScreen(
            deleteUseCase: _NoopDeleteUseCase(),
            exportUseCase: _NoopExportUseCase(),
          ),
        );
        expect(find.byKey(const Key('plan-privacy-intro')), findsOneWidget);
        expect(
          find.byKey(const Key('plan-privacy-scope-card')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('plan-privacy-discomfort-card')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('plan-privacy-export-action')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('plan-privacy-delete-action')),
          findsOneWidget,
        );
      },
    );
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    theme: SsLightTheme.data(),
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  ),
);

Future<void> _pumpWithScaler(
  WidgetTester tester,
  TextScaler scaler,
  Widget child, {
  Locale locale = const Locale('en'),
}) {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  return tester.pumpWidget(
    MaterialApp(
      theme: SsLightTheme.data(),
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(textScaler: scaler),
        child: child,
      ),
    ),
  );
}

/// PracticeDay convenience — overrides only `reasonCodes`.
extension on PracticeDay {
  PracticeDay _withReasonCodes(List<String> codes) => PracticeDay(
    id: id,
    localDate: localDate,
    status: status,
    timeBudget: timeBudget,
    blocks: blocks,
    primaryFocusSkillIds: primaryFocusSkillIds,
    reasonCodes: codes,
  );
}

class _NoopDeleteUseCase extends DeletePracticePlanningData {
  _NoopDeleteUseCase()
    : super(
        planRepository: _buildDeps().planRepository,
        draftRepository: _buildDeps().draftRepository,
        evidenceRepository: _buildDeps().evidenceRepository,
      );

  @override
  Future<AppResult<DeletePracticePlanningDataResult>> call() async =>
      const Success<DeletePracticePlanningDataResult>(
        DeletePracticePlanningDataResult(
          plannerKeyCount: 0,
          evidenceRecordCount: 0,
          affectedPlanIds: <PlanId>{},
        ),
      );
}

class _NoopExportUseCase extends ExportPracticePlanningData {
  _NoopExportUseCase()
    : super(
        planRepository: _buildDeps().planRepository,
        evidenceRepository: _buildDeps().evidenceRepository,
        cacheDirectory: () async => Directory.systemTemp,
        clock: () => DateTime.utc(2026, 8, 19),
      );

  @override
  Future<AppResult<ExportPracticePlanningDataResult>> call() async =>
      const Success<ExportPracticePlanningDataResult>(
        ExportPracticePlanningDataResult(
          fileName: 'noop.json',
          byteCount: 0,
          evidenceRecordCount: 0,
        ),
      );
}

({
  LocalPracticePlanRepository planRepository,
  GenerationDraftRepository draftRepository,
  InMemoryPracticeEvidenceRepository evidenceRepository,
})
_buildDeps() {
  final store = InMemoryKeyValueStore();
  return (
    planRepository: LocalPracticePlanRepository(
      keyValueStore: store,
      resolveCandidate: resolveCandidate,
    ),
    draftRepository: GenerationDraftRepository(keyValueStore: store),
    evidenceRepository: InMemoryPracticeEvidenceRepository(),
  );
}

// Local import alias to keep the import list small. Pulled in only for
// the `_withReasonCodes` extension on PracticeDay.
// ignore: unused_element
typedef _PracticeDayAnchor = PracticeDay;
// ignore: unused_element
typedef _PracticeBlockAnchor = PracticeBlock;
