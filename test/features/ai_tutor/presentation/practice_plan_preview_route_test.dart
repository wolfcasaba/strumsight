// R9 — the practice-plan preview end to end: a real draft is produced from
// the shipped exercise catalog, rendered by the existing screen, and an
// accepted plan is actually written to the Practice Generator's local
// repository (read back through that repository's own public API, so the
// cell measures persistence rather than a callback firing).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/app/routing/app_router.dart';
import 'package:strumsight/core/design_system/public.dart';
import 'package:strumsight/features/ai_tutor/presentation/practice_plan_preview_route.dart';
import 'package:strumsight/features/ai_tutor/presentation/providers/tutor_plan_providers.dart';
import 'package:strumsight/features/practice_generator/public.dart'
    show
        PracticeCatalogSnapshot,
        ExerciseCandidate,
        localPracticePlanRepositoryProvider,
        practiceCatalogSnapshotProvider,
        practiceGeneratorClockProvider;
import 'package:strumsight/features/onboarding/onboarding_provider.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/l10n/app_localizations_en.dart';

import '../../../support/preference_store.dart';

AppLocalizations _l10n() => AppLocalizationsEn();

/// Pumps the route. [catalog] substitutes the exercise catalog; the default
/// is the real shipped one, so the happy-path cells measure production data.
///
/// The parameter is a catalog, not an override list, on purpose: naming
/// `Override` as a type needs `package:flutter_riverpod/misc.dart`, which
/// `flutter_riverpod.dart` does not re-export (measured on CI), and the
/// inferred list literal below needs no such import.
Future<ProviderContainer> _pump(
  WidgetTester tester, {
  PracticeCatalogSnapshot? catalog,
}) async {
  // A tall surface so the whole plan (4 block cards + the Save/Start row)
  // is laid out — a 600px default would leave the actions unbuilt.
  tester.view.physicalSize = const Size(1400, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final overrides = [
    ...preferenceOverrides(),
    practiceGeneratorClockProvider.overrideWithValue(
      () => DateTime.utc(2026, 9, 7, 10),
    ),
  ];
  if (catalog != null) {
    overrides.add(practiceCatalogSnapshotProvider.overrideWithValue(catalog));
  }
  final container = ProviderContainer(overrides: overrides);
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: SsLightTheme.data(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const PracticePlanPreviewRoute(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the preview renders a real produced draft', (tester) async {
    final container = await _pump(tester);

    final catalog = container.read(practiceCatalogSnapshotProvider);
    expect(catalog.candidates, isNotEmpty);
    expect(
      find.text(_l10n().aiTutorPlanTotalDuration(20)),
      findsOneWidget,
      reason: 'the default 20-minute plan length is rendered as a total',
    );
    // Four five-minute blocks: the exact split the producer measures out.
    expect(find.textContaining('5 minutes'), findsNWidgets(4));
    expect(find.byKey(const ValueKey('plan-save')), findsOneWidget);
  });

  testWidgets('accepting the plan persists it as the ACTIVE plan', (
    tester,
  ) async {
    final container = await _pump(tester);
    final repository = container.read(localPracticePlanRepositoryProvider);

    final before = await repository.readActivePlan();
    expect(before.valueOrNull, isNull);

    await tester.tap(find.byKey(const ValueKey('plan-save')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('ss-tool-confirmation-confirm')),
    );
    await tester.pumpAndSettle();

    final after = await repository.readActivePlan();
    final plan = after.valueOrNull;
    expect(plan, isNotNull, reason: 'accept must write through to storage');
    expect(plan!.days, hasLength(1));
    expect(plan.days.single.blocks, hasLength(4));
    expect(plan.title, _l10n().tutorPlanDraftTitle(20));
    expect(find.text(_l10n().tutorPlanSaved), findsOneWidget);
  });

  testWidgets('an edited block length is what gets persisted', (tester) async {
    final container = await _pump(tester);
    final repository = container.read(localPracticePlanRepositoryProvider);

    final increase = find.byWidgetPredicate(
      (widget) =>
          widget is IconButton &&
          widget.key.toString().contains('plan-increase-'),
    );
    await tester.tap(increase.first);
    await tester.pumpAndSettle();

    expect(find.text(_l10n().aiTutorPlanTotalDuration(21)), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('plan-save')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('ss-tool-confirmation-confirm')),
    );
    await tester.pumpAndSettle();

    final after = await repository.readActivePlan();
    expect(after.valueOrNull, isNotNull);
    expect(
      after.valueOrNull!.days.single.timeBudget,
      const Duration(minutes: 21),
      reason: 'the persisted plan carries the edit, not the proposal',
    );
  });

  testWidgets('an empty catalog shows an honest unavailable state instead '
      'of an empty plan', (tester) async {
    await _pump(
      tester,
      catalog: PracticeCatalogSnapshot(
        catalogRevision: 'test-catalog',
        contentRevision: 'test-content',
        candidates: const <ExerciseCandidate>[],
      ),
    );

    expect(
      find.byKey(const ValueKey('tutor-plan-unavailable')),
      findsOneWidget,
    );
    expect(find.text(_l10n().tutorPlanCatalogEmpty), findsOneWidget);
    expect(find.byKey(const ValueKey('plan-save')), findsNothing);
  });

  testWidgets('changing the requested length reproduces the draft', (
    tester,
  ) async {
    final container = await _pump(tester);

    container.read(tutorPlanLengthProvider.notifier).setMinutes(10);
    await tester.pumpAndSettle();

    expect(find.text(_l10n().aiTutorPlanTotalDuration(10)), findsOneWidget);
  });

  test('the /tutor/plan-preview route is registered behind the tutor flag', () {
    final container = ProviderContainer(
      overrides: [
        ...preferenceOverrides(),
        onboardingSeenProvider.overrideWith(() => OnboardingController(true)),
        appConfigProvider.overrideWithValue(_tutorConfig()),
      ],
    );
    addTearDown(container.dispose);

    final router = container.read(routerProvider);
    final paths = _routePaths(router.configuration.routes);

    expect(paths, contains(AppRoutes.tutorPlanPreview));
  });

  test('the route disappears with the tutor flag off — a KI build must not '
      'expose the preview at all', () {
    final container = ProviderContainer(
      overrides: [
        ...preferenceOverrides(),
        onboardingSeenProvider.overrideWith(() => OnboardingController(true)),
        appConfigProvider.overrideWithValue(_tutorConfig(aiTutor: false)),
      ],
    );
    addTearDown(container.dispose);

    final router = container.read(routerProvider);
    final paths = _routePaths(router.configuration.routes);

    expect(paths, isNot(contains(AppRoutes.tutorPlanPreview)));
  });
}

AppConfig _tutorConfig({bool aiTutor = true}) => AppConfig(
  environment: AppEnvironment.development,
  apiBaseUrl: AppConfig.devApiBaseUrl,
  flags: FeatureFlags(
    accountEnabled: false,
    diagnosticsEnabled: false,
    labModeAvailable: false,
    aiTutorEnabled: aiTutor,
  ),
  diagnosticsToken: AppConfig.devDiagnosticsToken,
  buildMode: 'test',
  appVersion: 'test',
);

List<String> _routePaths(List<RouteBase> routes) {
  final paths = <String>[];
  for (final route in routes) {
    if (route is GoRoute) paths.add(route.path);
    paths.addAll(_routePaths(route.routes));
  }
  return paths;
}
