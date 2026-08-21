import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/public.dart';
import 'package:strumsight/core/theme/app_theme.dart';

void main() {
  group('component catalog access', () {
    test('is default-off at compile time', () {
      expect(ComponentCatalog.isCompileTimeEnabled, isFalse);
      expect(ComponentCatalog.createRoute(), isNull);
    });

    for (final gates in const [
      (catalogEnabled: false, debugBuild: false),
      (catalogEnabled: false, debugBuild: true),
      (catalogEnabled: true, debugBuild: false),
    ]) {
      test('does not create a route when gates are $gates', () {
        final route = ComponentCatalog.createRouteForTesting(
          catalogEnabled: gates.catalogEnabled,
          debugBuild: gates.debugBuild,
        );

        expect(route, isNull);
      });
    }
  });

  test('keeps the catalog screen library-private behind the route factory', () {
    final source = File(
      'lib/core/design_system/documentation/component_catalog_screen.dart',
    ).readAsStringSync();

    expect(source, contains('final class _ComponentCatalogScreen'));
    expect(source, isNot(contains('class ComponentCatalogScreen')));
    expect(source, contains('builder: (_) => const _ComponentCatalogScreen()'));
  });

  testWidgets('creates the catalog only when both gates pass', (tester) async {
    final route = ComponentCatalog.createRouteForTesting(
      catalogEnabled: true,
      debugBuild: true,
    );
    expect(route, isNotNull);

    await tester.pumpWidget(MaterialApp(onGenerateRoute: (_) => route));
    await tester.pumpAndSettle();
    expect(find.byType(Card), findsOneWidget);
  });

  for (final theme in [AppTheme.dark(), AppTheme.light()]) {
    testWidgets('catalog smoke test renders for ${theme.brightness}', (
      tester,
    ) async {
      final route = ComponentCatalog.createRouteForTesting(
        catalogEnabled: true,
        debugBuild: true,
      );
      expect(route, isNotNull);

      await tester.pumpWidget(
        MaterialApp(theme: theme, onGenerateRoute: (_) => route),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Card), findsOneWidget);
      expect(find.byType(DecoratedBox), findsOneWidget);
    });
  }
}
