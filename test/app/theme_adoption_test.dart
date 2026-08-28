// E15-R01 — proves the app's ACTUAL runtime theme is the design-system
// theme (ADR 0466 D1-D4): the MaterialApp built by StrumSightApp (and
// its bootstrap-failure error path) carries the four design-system theme
// extensions in both brightnesses, a design-system component resolves
// those tokens without a feature-level `*ThemeScope` wrapper, and the
// adoption is additive-only (legacy colorScheme/textTheme/scaffold
// background are unchanged, ADR 0466 D2).
//
// Each test reads the theme off the ACTUALLY PUMPED `MaterialApp` widget
// (`tester.widget<MaterialApp>(...)`), never `SsLightTheme.data()` /
// `SsDarkTheme.data()` called directly — the thing under measurement is
// the app, not the theme class (round brief §6).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:strumsight/app/strumsight_app.dart';
import 'package:strumsight/core/design_system/public.dart';
import 'package:strumsight/core/theme/app_theme.dart';
import 'package:strumsight/features/live/providers/live_providers.dart';

import '../support/fake_engines.dart';
import '../support/preference_store.dart';

Future<MaterialApp> _pumpApp(WidgetTester tester) async {
  final engine = FakeStrumEngine();
  addTearDown(engine.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...preferenceOverrides(),
        strumEngineProvider.overrideWithValue(engine),
      ],
      child: const StrumSightApp(),
    ),
  );
  await tester.pumpAndSettle();

  return tester.widget<MaterialApp>(find.byType(MaterialApp));
}

void main() {
  testWidgets(
    'A1: the running app theme carries all four design-system extensions, '
    'light and dark',
    (tester) async {
      final app = await _pumpApp(tester);

      for (final theme in [app.theme, app.darkTheme]) {
        expect(theme, isNotNull);
        expect(
          theme!.extension<SsColorScheme>(),
          isNotNull,
          reason: 'SsColorScheme missing from the app theme',
        );
        expect(
          theme.extension<SsTypography>(),
          isNotNull,
          reason: 'SsTypography missing from the app theme',
        );
        expect(
          theme.extension<SsStateOverlays>(),
          isNotNull,
          reason: 'SsStateOverlays missing from the app theme',
        );
        expect(
          theme.extension<SsThemeBehavior>(),
          isNotNull,
          reason: 'SsThemeBehavior missing from the app theme',
        );
      }
    },
  );

  testWidgets(
    'A2: a design-system component resolves tokens without a ThemeScope '
    'wrapper, under the app theme',
    (tester) async {
      final app = await _pumpApp(tester);

      final captured = <FlutterErrorDetails>[];
      final previousOnError = FlutterError.onError;
      FlutterError.onError = captured.add;
      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: app.theme,
            home: Scaffold(
              body: SsButton(label: 'Adopted', onPressed: () {}),
            ),
          ),
        );
        await tester.pumpAndSettle();
      } finally {
        FlutterError.onError = previousOnError;
      }

      expect(
        captured,
        isEmpty,
        reason:
            'a design-system component must resolve its tokens from the '
            'app theme without a *ThemeScope wrapper (ADR 0466 D1); got: '
            '${captured.map((d) => d.exception).toList()}',
      );
      expect(find.text('Adopted'), findsOneWidget);
    },
  );

  testWidgets(
    'A3: the bootstrap-failure recovery screen also gets the design-system '
    'theme',
    (tester) async {
      await tester.pumpWidget(
        const BootstrapFailureApp(problems: ['test problem']),
      );
      await tester.pumpAndSettle();

      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      final theme = app.theme;
      expect(theme, isNotNull);
      final expected = SsDarkTheme.data();

      expect(
        theme!.extension<SsColorScheme>(),
        equals(expected.extension<SsColorScheme>()),
      );
      expect(theme.extension<SsTypography>(), isNotNull);
      expect(
        theme.extension<SsStateOverlays>(),
        equals(expected.extension<SsStateOverlays>()),
      );
      expect(
        theme.extension<SsThemeBehavior>(),
        equals(expected.extension<SsThemeBehavior>()),
      );
    },
  );

  testWidgets(
    'A7: the app theme colorScheme/textTheme/scaffoldBackgroundColor equal '
    'the legacy AppTheme (additive-only adoption, ADR 0466 D2)',
    (tester) async {
      final app = await _pumpApp(tester);
      final legacyLight = AppTheme.light();
      final legacyDark = AppTheme.dark();

      expect(app.theme!.colorScheme, equals(legacyLight.colorScheme));
      expect(app.theme!.textTheme, equals(legacyLight.textTheme));
      expect(
        app.theme!.scaffoldBackgroundColor,
        equals(legacyLight.scaffoldBackgroundColor),
      );

      expect(app.darkTheme!.colorScheme, equals(legacyDark.colorScheme));
      expect(app.darkTheme!.textTheme, equals(legacyDark.textTheme));
      expect(
        app.darkTheme!.scaffoldBackgroundColor,
        equals(legacyDark.scaffoldBackgroundColor),
      );
    },
  );

  test('A6: every production screen source can now resolve tokens from the '
      'app theme (ADR 0466 D1) — count must match '
      'docs/ui/migration-status.md and tool/ui_inventory.dart', () {
    final screenCount = Directory('lib/features')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('_screen.dart'))
        .length;

    expect(
      screenCount,
      96,
      reason:
          'the MaterialApp theme now carries the design-system '
          'extensions for the whole tree (D1), so every production '
          'screen — migrated or not — resolves tokens from the same '
          'ThemeData, not just the previously-wrapped subset',
    );
  });

  test('A8: strumsight_app.dart imports the design-system theme through the '
      'public barrel (ADR 0466 D3), not the theme files directly', () {
    final source = File('lib/app/strumsight_app.dart').readAsStringSync();

    expect(source, contains('design_system/public.dart'));
    expect(source, isNot(contains('themes/ss_light_theme.dart')));
    expect(source, isNot(contains('themes/ss_dark_theme.dart')));
  });
}
