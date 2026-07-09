import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/router.dart';
import 'core/i18n/locale_provider.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_mode_provider.dart';
import 'features/onboarding/onboarding_provider.dart';
import 'features/settings/providers/settings_sync.dart';
import 'l10n/app_localizations.dart';

Future<void> main() async {
  // StrumSight is fully offline / on-device — no backend init, no network.
  WidgetsFlutterBinding.ensureInitialized();
  // Load the first-run flag before the first frame so the router can gate on it
  // synchronously (no onboarding flicker for returning users).
  final onboardingSeen = await OnboardingController.load();
  runApp(
    ProviderScope(
      overrides: [
        onboardingSeenProvider
            .overrideWith(() => OnboardingController(onboardingSeen)),
      ],
      child: const StrumSightApp(),
    ),
  );
}

class StrumSightApp extends ConsumerWidget {
  const StrumSightApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);
    final router = ref.watch(routerProvider);
    // Instantiate the settings-sync listener for the app's lifetime (inert
    // while logged out; pulls on sign-in, pushes local changes when signed in).
    ref.watch(settingsSyncProvider);

    return MaterialApp.router(
      title: 'StrumSight',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      locale: locale,
      routerConfig: router,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
    );
  }
}
