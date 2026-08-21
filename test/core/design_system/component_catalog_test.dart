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

  testWidgets('creates the catalog only when both gates pass', (tester) async {
    final route = ComponentCatalog.createRouteForTesting(
      catalogEnabled: true,
      debugBuild: true,
    );
    expect(route, isNotNull);

    await tester.pumpWidget(MaterialApp(home: ComponentCatalogScreen()));
    expect(find.byType(ComponentCatalogScreen), findsOneWidget);
    expect(find.byType(Card), findsOneWidget);
  });

  for (final theme in [AppTheme.dark(), AppTheme.light()]) {
    testWidgets('catalog smoke test renders for ${theme.brightness}', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(theme: theme, home: const ComponentCatalogScreen()),
      );

      expect(find.byType(ComponentCatalogScreen), findsOneWidget);
      expect(find.byType(DecoratedBox), findsOneWidget);
    });
  }
}
