// WP-H2 (2026-09-06) — the entry point for the tutor's practice-plan preview.
//
// `PracticePlanPreviewScreen` was one of the three measured-unreachable
// screens (`dart run tool/check_screen_reachability.dart`): no route named it
// and nothing in `lib/` constructed it. These cells measure the whole edge —
// the Tutor Home CTA compiles a plan from live app data and pushes it as
// `extra`, the route renders the screen, and the redirect guard sends a
// wrong-typed / missing `extra` back to Tutor Home instead of crashing on the
// cast.
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
import 'package:strumsight/features/ai_tutor/presentation/practice_plan_preview_args.dart';
import 'package:strumsight/features/ai_tutor/presentation/screens/practice_plan_preview_screen.dart';
import 'package:strumsight/features/ai_tutor/presentation/screens/tutor_home_screen.dart';
import 'package:strumsight/features/onboarding/onboarding_provider.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/l10n/app_localizations_en.dart';

import '../../support/preference_store.dart';

class _RouterTestApp extends ConsumerWidget {
  const _RouterTestApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
    theme: SsLightTheme.data(),
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    routerConfig: ref.watch(routerProvider),
  );
}

Future<GoRouter> _pumpTutorRouter(
  WidgetTester tester, {
  bool practiceEngineV2Enabled = true,
  List<Override> extraOverrides = const <Override>[],
}) async {
  final container = ProviderContainer(
    overrides: <Override>[
      ...preferenceOverrides(),
      onboardingSeenProvider.overrideWith(() => OnboardingController(true)),
      appConfigProvider.overrideWithValue(
        AppConfig(
          environment: AppEnvironment.development,
          apiBaseUrl: AppConfig.devApiBaseUrl,
          flags: FeatureFlags(
            accountEnabled: false,
            diagnosticsEnabled: false,
            labModeAvailable: false,
            aiTutorEnabled: true,
            practiceEngineV2Enabled: practiceEngineV2Enabled,
          ),
          diagnosticsToken: AppConfig.devDiagnosticsToken,
          buildMode: 'test',
          appVersion: 'test',
        ),
      ),
      ...extraOverrides,
    ],
  );
  final router = container.read(routerProvider);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const _RouterTestApp(),
    ),
  );
  await tester.pumpAndSettle();
  router.go(AppRoutes.tutorHome);
  await tester.pumpAndSettle();
  return router;
}

/// The preview renders in a `ListView`, so the action row is off-screen at the
/// default 800x600 test viewport and is not built at all. Scroll it in first.
Future<void> _scrollToActions(WidgetTester tester, Key key) async {
  await tester.scrollUntilVisible(
    find.byKey(key),
    300,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.pumpAndSettle();
}

void main() {
  final l10n = AppLocalizationsEn();

  testWidgets('the Tutor Home CTA compiles a plan and pushes the preview', (
    tester,
  ) async {
    final router = await _pumpTutorRouter(tester);
    expect(find.byType(TutorHomeScreen), findsOneWidget);

    await tester.tap(find.byKey(const Key('tutorHomePracticePlanCta')));
    await tester.pumpAndSettle();

    expect(router.state.uri.path, AppRoutes.tutorPracticePlanPreview);
    expect(router.state.extra, isA<TutorPracticePlanPreviewArgs>());
    expect(find.byType(PracticePlanPreviewScreen), findsOneWidget);

    // The plan is REAL: the blocks are bound to shipped catalog exercises,
    // not to an empty template.
    final args = router.state.extra! as TutorPracticePlanPreviewArgs;
    expect(args.compilationContext.practiceTargets, isNotEmpty);
    expect(args.draft.blocks, isNotEmpty);
    expect(
      find.text(l10n.aiTutorPlanPreviewTitle(args.draft.title)),
      findsOneWidget,
    );
  });

  testWidgets('a MISSING extra redirects back to Tutor Home', (tester) async {
    final router = await _pumpTutorRouter(tester);

    router.go(AppRoutes.tutorPracticePlanPreview);
    await tester.pumpAndSettle();

    expect(router.state.uri.path, AppRoutes.tutorHome);
    expect(find.byType(PracticePlanPreviewScreen), findsNothing);
    expect(find.byType(TutorHomeScreen), findsOneWidget);
  });

  testWidgets('a WRONG-TYPED extra redirects back to Tutor Home', (
    tester,
  ) async {
    final router = await _pumpTutorRouter(tester);

    router.go(AppRoutes.tutorPracticePlanPreview, extra: 'not-a-plan');
    await tester.pumpAndSettle();

    expect(router.state.uri.path, AppRoutes.tutorHome);
    expect(find.byType(PracticePlanPreviewScreen), findsNothing);
  });

  testWidgets('save is DISABLED and says why — there is no receiving side', (
    tester,
  ) async {
    final router = await _pumpTutorRouter(tester);
    await tester.tap(find.byKey(const Key('tutorHomePracticePlanCta')));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, AppRoutes.tutorPracticePlanPreview);
    await _scrollToActions(tester, const ValueKey('plan-save-unavailable'));

    expect(
      tester
          .widget<ElevatedButton>(find.byKey(const ValueKey('plan-save')))
          .onPressed,
      isNull,
    );
    expect(find.byKey(const ValueKey('plan-save-unavailable')), findsOneWidget);
    expect(find.text(l10n.aiTutorPlanSaveUnavailable), findsOneWidget);

    // Start, by contrast, is live: the practice engine is on in this build.
    expect(
      tester
          .widget<ButtonStyleButton>(find.byKey(const ValueKey('plan-start')))
          .onPressed,
      isNotNull,
    );
    expect(find.byKey(const ValueKey('plan-start-unavailable')), findsNothing);
  });

  testWidgets('with the practice engine OFF, start says so instead of '
      'pretending', (tester) async {
    final router = await _pumpTutorRouter(
      tester,
      practiceEngineV2Enabled: false,
    );
    await tester.tap(find.byKey(const Key('tutorHomePracticePlanCta')));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, AppRoutes.tutorPracticePlanPreview);
    await _scrollToActions(tester, const ValueKey('plan-start-unavailable'));

    expect(
      tester
          .widget<ButtonStyleButton>(find.byKey(const ValueKey('plan-start')))
          .onPressed,
      isNull,
    );
    expect(find.text(l10n.aiTutorPlanStartUnavailable), findsOneWidget);
  });
}
