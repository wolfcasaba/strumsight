import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/audio/audio_providers.dart';
import '../core/i18n/locale_provider.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/theme_mode_provider.dart';
import '../features/settings/providers/settings_sync.dart';
import '../l10n/app_localizations.dart';
import 'router.dart';

/// The root widget (moved out of main.dart in E01-R03 §3.4 — main stays
/// minimal, the app shell lives here).
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
    // The mic must die when the app leaves the foreground (E01-R09 §9.4) —
    // the guard only does that while something keeps it alive.
    ref.watch(audioLifecycleGuardProvider);

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

/// Shown instead of the app when bootstrap fails (E01-R03): a deliberately
/// minimal, provider-free MaterialApp — configuration is broken, so nothing
/// that depends on it may run. Fail-closed, but with a readable reason.
class BootstrapFailureApp extends StatelessWidget {
  const BootstrapFailureApp({required this.problems, super.key});

  final List<String> problems;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'StrumSight',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) {
          final l10n = AppLocalizations.of(context);
          return Scaffold(
            body: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 56),
                      const SizedBox(height: 16),
                      Text(
                        l10n.bootstrapFailureTitle,
                        style: Theme.of(context).textTheme.titleLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.bootstrapFailureBody,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      for (final p in problems)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            '• $p',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
