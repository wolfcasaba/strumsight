import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/app/routing/app_router.dart';
import 'package:strumsight/core/design_system/themes/ss_light_theme.dart';
import 'package:strumsight/core/storage/storage_keys.dart';
import 'package:strumsight/core/storage/storage_providers.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../../core/storage/in_memory_key_value_store.dart';

AppConfig _config(bool visionEnabled) => AppConfig(
  environment: AppEnvironment.development,
  apiBaseUrl: AppConfig.devApiBaseUrl,
  flags: FeatureFlags(
    accountEnabled: false,
    diagnosticsEnabled: false,
    labModeAvailable: false,
    visionEnabled: visionEnabled,
  ),
  diagnosticsToken: AppConfig.devDiagnosticsToken,
  buildMode: 'test',
  appVersion: 'test',
);

ProviderContainer _container(bool visionEnabled) => ProviderContainer(
  overrides: [
    appConfigProvider.overrideWithValue(_config(visionEnabled)),
    keyValueStoreProvider.overrideWithValue(
      InMemoryKeyValueStore(<String, Object>{StorageKeys.onboardingSeen: true}),
    ),
  ],
);

Future<void> _pumpRouter(WidgetTester tester, ProviderContainer container) =>
    tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (context, ref, _) => MaterialApp.router(
            // §0.0/R9: the route reaches the migrated VisionSessionScreen,
            // which reads the design-system theme extensions — a themeless
            // MaterialApp.router null-check crashes (L593-class defect).
            theme: SsLightTheme.data(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: ref.watch(routerProvider),
          ),
        ),
      ),
    );

void main() {
  testWidgets('Vision session route is registered behind only visionEnabled', (
    tester,
  ) async {
    final container = _container(true);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });
    final router = container.read(routerProvider);
    await _pumpRouter(tester, container);
    await tester.pumpAndSettle();

    router.go(AppRoutes.visionSession);
    await tester.pumpAndSettle();

    expect(router.state.uri.path, AppRoutes.visionSession);
  });

  testWidgets('Vision session route is absent when visionEnabled is off', (
    tester,
  ) async {
    final container = _container(false);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });
    final router = container.read(routerProvider);
    await _pumpRouter(tester, container);
    await tester.pumpAndSettle();

    router.go(AppRoutes.visionSession);
    await tester.pumpAndSettle();

    expect(router.state.uri.path, AppRoutes.live);
  });
}
