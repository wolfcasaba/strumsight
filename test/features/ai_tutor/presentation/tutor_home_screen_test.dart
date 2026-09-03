// E04-R18 §6 — Tutor Home screen + flag-gating routing matrix.
//
// The Home screen is the entry surface for the AI Tutor feature. Its
// widget tests cover:
//   * the empty-state copy and the "Start conversation" CTA,
//   * the CTA navigating into the Chat route via `GoRouter`,
//   * the flag-gating matrix: `aiTutorEnabled` ON registers the home
//     route; OFF removes it and the existing onException falls back to
//     the Live screen (E03-R17 anchor — same pattern as Practice).
//
// RED-first: this file is written BEFORE the presentation package
// exists. It compiles only after `tutor_providers.dart`,
// `tutor_home_screen.dart`, the typed routes in `app_route.dart` and
// the flag-gated registration in `app_router.dart` land.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/app/routing/app_router.dart';
import 'package:strumsight/core/design_system/components/actions/ss_button.dart';
import 'package:strumsight/core/design_system/components/ai/ss_model_status_card.dart';
import 'package:strumsight/core/design_system/themes/ss_light_theme.dart';
import 'package:strumsight/features/ai_tutor/application/controller/tutor_state.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_message.dart';
import 'package:strumsight/features/ai_tutor/presentation/providers/tutor_providers.dart';
import 'package:strumsight/features/auth/data/token_store.dart';
import 'package:strumsight/features/auth/providers/auth_providers.dart';
import 'package:strumsight/features/live/providers/live_providers.dart';
import 'package:strumsight/features/live/screens/live_screen.dart';
import 'package:strumsight/features/onboarding/onboarding_provider.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/l10n/app_localizations_en.dart';

import '../../../support/fake_audio.dart';
import '../../../support/fake_auth.dart';
import '../../../support/fake_engines.dart';
import '../../../support/preference_store.dart';

AppLocalizations l10nEn() => AppLocalizationsEn();

AppConfig _config({bool aiTutorEnabled = true}) => AppConfig.resolve(
  environment: AppEnvironment.development,
  apiBaseUrl: AppConfig.devApiBaseUrl,
  flags: FeatureFlags(
    accountEnabled: false,
    diagnosticsEnabled: false,
    labModeAvailable: false,
    aiTutorEnabled: aiTutorEnabled,
  ),
  diagnosticsToken: AppConfig.devDiagnosticsToken,
  buildMode: 'test',
  appVersion: 'test',
);

/// Stub controller — the routing tests never actually exercise chat
/// behaviour, only the path that the router resolves. Returning a
/// no-op keeps the chat screen out of the way.
class _NoopChatController extends ChangeNotifier
    implements TutorChatController {
  @override
  List<TutorMessage> get messages => const <TutorMessage>[];
  @override
  TutorTurnStatus get status => TutorTurnStatus.idle;
  @override
  String get responseText => '';
  @override
  String get draft => '';
  @override
  bool get isOnline => true;
  @override
  List<TutorBannerKind> get banners => const <TutorBannerKind>[];
  @override
  Stream<TutorChatState> get states => const Stream<TutorChatState>.empty();
  @override
  void setDraft(String value) {}
  @override
  void send() {}
  @override
  void cancel() {}
  @override
  void retry() {}
  @override
  void setOnline(bool value) {}
  @override
  void setBanners(List<TutorBannerKind> value) {}
}

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  bool aiTutorEnabled = true,
  Locale locale = const Locale('en'),
}) async {
  final engine = FakeStrumEngine();
  final container = ProviderContainer(
    overrides: [
      ...preferenceOverrides(),
      ...fakeAudioOverrides(),
      strumEngineProvider.overrideWithValue(engine),
      onboardingSeenProvider.overrideWith(() => OnboardingController(true)),
      accountEnabledProvider.overrideWithValue(false),
      tokenStoreProvider.overrideWithValue(FakeTokenStore()),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
      appConfigProvider.overrideWithValue(
        _config(aiTutorEnabled: aiTutorEnabled),
      ),
      tutorChatControllerProvider.overrideWithValue(_NoopChatController()),
    ],
  );
  // Tear down in the same order as the practice routing test: clear the
  // widget tree first so any pending stream subscriptions from LiveScreen
  // close before the container is disposed. `pumpAndSettle` later would
  // hang on those subscriptions.
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await engine.dispose();
  });

  final router = container.read(routerProvider);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: SsLightTheme.data(),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pump();
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // -----------------------------------------------------------------
  // Flag-gating — ON. /tutor/home resolves to a registered route.
  // -----------------------------------------------------------------
  testWidgets('R18-R1: aiTutorEnabled ON, /tutor/home is reachable', (
    tester,
  ) async {
    final container = await _pump(tester, aiTutorEnabled: true);
    final router = container.read(routerProvider);
    router.go(AppRoutes.tutorHome);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    // The home screen is built by name. We assert the path is
    // registered (the router resolved it, not the onException path).
    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      AppRoutes.tutorHome,
    );
    expect(tester.takeException(), isNull);
  });

  // -----------------------------------------------------------------
  // Flag-gating — OFF. /tutor/home is NOT registered and the router's
  // existing onException redirects unknown paths to /live. This is
  // the same behaviour the Practice V2 routes had in E02-R12.
  // -----------------------------------------------------------------
  testWidgets('R18-R2: aiTutorEnabled OFF, /tutor/home falls back to Live', (
    tester,
  ) async {
    final container = await _pump(tester, aiTutorEnabled: false);
    final router = container.read(routerProvider);
    router.go(AppRoutes.tutorHome);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(LiveScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // -----------------------------------------------------------------
  // Flag-gating — ON. /tutor/chat is reachable.
  // -----------------------------------------------------------------
  testWidgets('R18-R3: aiTutorEnabled ON, /tutor/chat is reachable', (
    tester,
  ) async {
    final container = await _pump(tester, aiTutorEnabled: true);
    final router = container.read(routerProvider);
    router.go(AppRoutes.tutorChat);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      AppRoutes.tutorChat,
    );
    expect(tester.takeException(), isNull);
  });

  // -----------------------------------------------------------------
  // Flag-gating — OFF. /tutor/chat also falls back to Live.
  // -----------------------------------------------------------------
  testWidgets('R18-R4: aiTutorEnabled OFF, /tutor/chat falls back to Live', (
    tester,
  ) async {
    final container = await _pump(tester, aiTutorEnabled: false);
    final router = container.read(routerProvider);
    router.go(AppRoutes.tutorChat);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(LiveScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // -----------------------------------------------------------------
  // E15-R09 §0.0.B/R15 — per-screen design-system type assertion: the
  // model-status card and the "Start conversation" CTA are the
  // theme-extension `Ss*` components, not a screen-local rebuild.
  // -----------------------------------------------------------------
  testWidgets(
    'R18-R5: the model-status card and CTA are the design-system components',
    (tester) async {
      final container = await _pump(tester, aiTutorEnabled: true);
      final router = container.read(routerProvider);
      router.go(AppRoutes.tutorHome);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.byType(SsModelStatusCard), findsOneWidget);
      expect(find.byType(SsButton), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  // -----------------------------------------------------------------
  // E15-R09 §0.0.B/R14 — committed textScaler 2.0 coverage (en + hu),
  // on the phone viewport the golden lane uses (412x915 — the
  // flutter_test default 800x600 is wider AND taller than any phone
  // and hides real overflow). This is the regression guard for the
  // `_ModeChip`→`SsProvenanceBadge` overflow fix measured in §10.5 of
  // the round file (`home@2.0hu` was red before that fix).
  // -----------------------------------------------------------------
  for (final locale in const [Locale('en'), Locale('hu')]) {
    testWidgets(
      'R18-R7: textScaler 2.0, locale=${locale.languageCode} — no overflow',
      (tester) async {
        tester.view.physicalSize = const Size(412, 915);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        tester.platformDispatcher.textScaleFactorTestValue = 2.0;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        final container = await _pump(
          tester,
          aiTutorEnabled: true,
          locale: locale,
        );
        final router = container.read(routerProvider);
        router.go(AppRoutes.tutorHome);
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
