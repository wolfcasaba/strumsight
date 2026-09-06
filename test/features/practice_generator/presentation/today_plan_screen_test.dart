import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/core/design_system/themes/ss_light_theme.dart';
import 'package:strumsight/features/practice_generator/public.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../../fixtures/practice_generator/validation/validation_fixtures.dart';

void main() {
  group('TodayPlanScreen', () {
    testWidgets('A1: no active plan renders a useful empty state', (
      tester,
    ) async {
      await _pump(
        tester,
        TodayPlanScreen(
          controller: TodayPlanController(clock: () => DateTime(2026, 8, 19)),
        ),
      );

      expect(find.byKey(const Key('today-plan-empty')), findsOneWidget);
      expect(find.text('No active plan yet'), findsOneWidget);
    });

    testWidgets('A2: rest day is never rendered as a missed day', (
      tester,
    ) async {
      final restDay = PracticeDay(
        id: DayId('rest-day'),
        localDate: LocalDate(2026, 8, 19),
        status: PracticeItemStatus.planned,
        timeBudget: const Duration(minutes: 30),
        blocks: const <PracticeBlock>[],
        primaryFocusSkillIds: const <String>['rest'],
        reasonCodes: <String>[ScheduleDecisionReason.restDay.code],
      );
      await _pump(
        tester,
        TodayPlanScreen(
          controller: TodayPlanController(clock: () => DateTime(2026, 8, 19)),
          plan: buildPlan(days: <PracticeDay>[restDay]),
        ),
      );

      expect(find.byKey(const Key('today-plan-rest-day')), findsOneWidget);
      expect(find.byKey(const Key('today-plan-missed-day')), findsNothing);
    });

    testWidgets(
      'A7: a rejected deep-link payload cannot expose an active plan',
      (tester) async {
        final launch = TodayPlanRouteRequest.tryParse(const <String, String>{
          'destination': 'today',
          'utm_source': 'push',
        });
        final plan = buildPlan(
          days: <PracticeDay>[
            buildDay(id: 'day.19', localDate: LocalDate(2026, 8, 19)),
          ],
        );

        await _pump(
          tester,
          TodayPlanScreen(
            controller: TodayPlanController(clock: () => DateTime(2026, 8, 19)),
            plan: plan,
            launchRequest: launch,
            isDeepLinkLaunch: true,
          ),
        );

        expect(launch, isNull);
        expect(find.byKey(const Key('today-plan-empty')), findsOneWidget);
        expect(find.byKey(const Key('today-plan-scheduled')), findsNothing);
      },
    );

    testWidgets('A7: a disabled Today deep link cannot expose an active plan', (
      tester,
    ) async {
      final launch = TodayPlanRouteRequest.tryParse(const <String, String>{
        'destination': 'today',
      });
      final plan = buildPlan(
        days: <PracticeDay>[
          buildDay(id: 'day.19', localDate: LocalDate(2026, 8, 19)),
        ],
      );

      await _pump(
        tester,
        TodayPlanScreen(
          controller: TodayPlanController(clock: () => DateTime(2026, 8, 19)),
          plan: plan,
          launchRequest: launch,
        ),
      );

      expect(find.byKey(const Key('today-plan-empty')), findsOneWidget);
      expect(find.byKey(const Key('today-plan-scheduled')), findsNothing);
    });

    testWidgets('week render distinguishes today, rest, and completed days', (
      tester,
    ) async {
      final rest = PracticeDay(
        id: DayId('rest-day'),
        localDate: LocalDate(2026, 8, 19),
        status: PracticeItemStatus.planned,
        timeBudget: const Duration(minutes: 30),
        blocks: const <PracticeBlock>[],
        primaryFocusSkillIds: const <String>['rest'],
        reasonCodes: <String>[ScheduleDecisionReason.restDay.code],
      );
      final completed = buildDay(
        id: 'completed-day',
        localDate: LocalDate(2026, 8, 20),
        status: PracticeItemStatus.completed,
      );

      await _pump(
        tester,
        WeeklyPlanScreen(
          plan: buildPlan(days: <PracticeDay>[rest, completed]),
          today: LocalDate(2026, 8, 19),
        ),
      );

      expect(find.byKey(const Key('weekly-plan-day-rest-day')), findsOneWidget);
      expect(
        find.byKey(const Key('weekly-plan-day-completed-day')),
        findsOneWidget,
      );
      expect(find.text('Rest day'), findsOneWidget);
      expect(find.text('Today is complete'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------
  // WP-D (2026-09-06) — a tervező két MELLÉK-képernyőjének belépési
  // pontja. MÉRT hiány: `/practice/generator/weekly` és `/privacy`
  // regisztrálva volt, de a szállított felületről SEMMI nem vezetett
  // rájuk. Az előnézet és a változás-áttekintés SZÁNDÉKOSAN nem kap itt
  // gombot: azok `extra`-t (tervet, illetve javaslatot) kérnek, amit ez a
  // képernyő nem tud előállítani — `extra` nélkül a router visszadobná
  // ide, azaz halott vezérlő lenne.
  // -------------------------------------------------------------------
  group('WP-D — the Today screen reaches the generator side-screens', () {
    for (final entry in const <({String key, String path})>[
      (key: 'today-plan-open-weekly', path: AppRoutes.practiceGeneratorWeekly),
      (
        key: 'today-plan-open-privacy',
        path: AppRoutes.practiceGeneratorPrivacy,
      ),
    ]) {
      testWidgets('${entry.key} navigates to ${entry.path}', (tester) async {
        await _pumpRouted(
          tester,
          TodayPlanScreen(
            controller: TodayPlanController(clock: () => DateTime(2026, 8, 19)),
          ),
        );

        await tester.tap(find.byKey(Key(entry.key)));
        await tester.pumpAndSettle();

        expect(find.text('STUB ${entry.path}'), findsOneWidget);
      });
    }
  });
}

/// WP-D harness — a valós „ma" képernyő egy MINIMÁLIS go_router alatt. A
/// két cél helyén `STUB <path>` áll: a cella a NAVIGÁCIÓT méri, nem a heti
/// terv / adatvédelem képernyő tartalmát (azoknak saját tesztjük van).
Future<void> _pumpRouted(WidgetTester tester, Widget child) {
  final router = GoRouter(
    initialLocation: AppRoutes.practiceGeneratorToday,
    routes: <RouteBase>[
      GoRoute(path: AppRoutes.practiceGeneratorToday, builder: (_, _) => child),
      for (final path in const <String>[
        AppRoutes.practiceGeneratorWeekly,
        AppRoutes.practiceGeneratorPrivacy,
      ])
        GoRoute(
          path: path,
          builder: (_, state) => Scaffold(body: Text('STUB ${state.uri.path}')),
        ),
    ],
  );
  return tester.pumpWidget(
    MaterialApp.router(
      theme: SsLightTheme.data(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  );
}

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    theme: SsLightTheme.data(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  ),
);
