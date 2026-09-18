// A2b — hub CTAs must `push`, never `go`.
//
// `go` REPLACES the current location, so the user lands on a screen with no
// back affordance and no way to return to the hub they came from; for the
// login route it is worse than a dead end, because `LoginScreen` pops itself
// on success and a popped-but-never-pushed route throws a `GoError`. The
// rule is documented at `practice_session_screen.dart` (~254-262). This file
// pins the three CTAs the audit found still calling `go`:
//   * Profile Hub → gamification hub,
//   * Profile Hub → login,
//   * Tutor Home → tutor chat.
// `today_hub_screen.dart` is deliberately out of scope here.
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
import 'package:strumsight/features/ai_tutor/application/controller/tutor_state.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_message.dart';
import 'package:strumsight/features/ai_tutor/presentation/providers/tutor_providers.dart';
import 'package:strumsight/features/ai_tutor/presentation/screens/tutor_chat_screen.dart';
import 'package:strumsight/features/ai_tutor/presentation/screens/tutor_home_screen.dart';
import 'package:strumsight/features/auth/data/token_store.dart';
import 'package:strumsight/features/auth/providers/auth_providers.dart';
import 'package:strumsight/features/auth/screens/login_screen.dart';
import 'package:strumsight/features/gamification/presentation/screens/gamification_hub_screen.dart';
import 'package:strumsight/features/live/providers/live_providers.dart';
import 'package:strumsight/features/onboarding/onboarding_provider.dart';
import 'package:strumsight/features/profile_hub/screens/profile_hub_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/l10n/app_localizations_en.dart';

import '../../support/fake_audio.dart';
import '../../support/fake_auth.dart';
import '../../support/fake_engines.dart';
import '../../support/preference_store.dart';

AppLocalizations _l10n() => AppLocalizationsEn();

/// Keeps the chat screen inert — these cells assert navigation, never chat
/// behaviour (same stub shape as `tutor_home_screen_test.dart`).
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

Future<GoRouter> _pumpRouterTo(
  WidgetTester tester,
  String location, {
  bool accountEnabled = false,
  bool aiTutorEnabled = false,
  List<Override> extraOverrides = const [],
}) async {
  final engine = FakeStrumEngine();
  final container = ProviderContainer(
    overrides: [
      ...preferenceOverrides(),
      ...fakeAudioOverrides(),
      ...extraOverrides,
      strumEngineProvider.overrideWithValue(engine),
      onboardingSeenProvider.overrideWith(() => OnboardingController(true)),
      accountEnabledProvider.overrideWithValue(accountEnabled),
      tokenStoreProvider.overrideWithValue(FakeTokenStore()),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
      tutorChatControllerProvider.overrideWithValue(_NoopChatController()),
      appConfigProvider.overrideWithValue(
        AppConfig(
          environment: AppEnvironment.development,
          apiBaseUrl: AppConfig.devApiBaseUrl,
          flags: FeatureFlags(
            accountEnabled: accountEnabled,
            diagnosticsEnabled: false,
            labModeAvailable: false,
            aiTutorEnabled: aiTutorEnabled,
            adaptiveShellEnabled: true,
          ),
          diagnosticsToken: AppConfig.devDiagnosticsToken,
          buildMode: 'test',
          appVersion: 'test',
        ),
      ),
    ],
  );
  final router = container.read(routerProvider);

  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await engine.dispose();
  });

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: SsLightTheme.data(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();

  router.go(location);
  await tester.pumpAndSettle();
  return router;
}

void main() {
  testWidgets(
    'Profile Hub achievements CTA pushes the gamification hub, leaving the '
    'hub on the stack',
    (tester) async {
      final router = await _pumpRouterTo(tester, AppRoutes.profileHome);
      expect(find.byType(ProfileHubScreen), findsOneWidget);

      final cta = find.widgetWithText(
        OutlinedButton,
        _l10n().profileHubAchievementsSectionTitle,
      );
      await tester.ensureVisible(cta);
      await tester.pumpAndSettle();
      await tester.tap(cta);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(router.state.uri.path, AppRoutes.gamificationHub);
      expect(find.byType(GamificationHubScreen), findsOneWidget);
      expect(router.canPop(), isTrue);

      router.pop();
      await tester.pumpAndSettle();

      expect(router.state.uri.path, AppRoutes.profileHome);
      expect(find.byType(ProfileHubScreen), findsOneWidget);
    },
  );

  testWidgets(
    'Profile Hub sign-in CTA pushes the login screen, so LoginScreen can pop '
    'itself without a GoError',
    (tester) async {
      final router = await _pumpRouterTo(
        tester,
        AppRoutes.profileHome,
        accountEnabled: true,
      );
      expect(find.byType(ProfileHubScreen), findsOneWidget);

      final cta = find.widgetWithText(
        OutlinedButton,
        _l10n().profileHubSignInCta,
      );
      await tester.ensureVisible(cta);
      await tester.pumpAndSettle();
      await tester.tap(cta);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(router.state.uri.path, AppRoutes.login);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(router.canPop(), isTrue);

      router.pop();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(router.state.uri.path, AppRoutes.profileHome);
      expect(find.byType(ProfileHubScreen), findsOneWidget);
    },
  );

  testWidgets(
    'Tutor Home start CTA pushes the chat screen, leaving Tutor Home on the '
    'stack',
    (tester) async {
      final router = await _pumpRouterTo(
        tester,
        AppRoutes.tutorHome,
        aiTutorEnabled: true,
      );
      expect(find.byType(TutorHomeScreen), findsOneWidget);

      final cta = find.byKey(const Key('tutorHomeStartCta'));
      await tester.ensureVisible(cta);
      await tester.pumpAndSettle();
      await tester.tap(cta);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(router.state.uri.path, AppRoutes.tutorChat);
      expect(find.byType(TutorChatScreen), findsOneWidget);
      expect(router.canPop(), isTrue);

      router.pop();
      await tester.pumpAndSettle();

      expect(router.state.uri.path, AppRoutes.tutorHome);
      expect(find.byType(TutorHomeScreen), findsOneWidget);
    },
  );
}
