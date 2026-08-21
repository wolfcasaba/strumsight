import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Development-only route factory for the component catalog.
abstract final class ComponentCatalog {
  /// Default-off compile-time switch for the development catalog.
  static const bool isCompileTimeEnabled = bool.fromEnvironment(
    'STRUMSIGHT_COMPONENT_CATALOG',
    defaultValue: false,
  );

  /// Creates a route only when the compile-time switch and debug build pass.
  static Route<void>? createRoute() {
    return _createRoute(
      catalogEnabled: isCompileTimeEnabled,
      debugBuild: kDebugMode,
    );
  }

  /// Exercises the same two-gate route rule with explicit test inputs.
  @visibleForTesting
  static Route<void>? createRouteForTesting({
    required bool catalogEnabled,
    required bool debugBuild,
  }) {
    return _createRoute(catalogEnabled: catalogEnabled, debugBuild: debugBuild);
  }

  static Route<void>? _createRoute({
    required bool catalogEnabled,
    required bool debugBuild,
  }) {
    if (!catalogEnabled || !debugBuild) return null;
    return MaterialPageRoute<void>(
      builder: (_) => const _ComponentCatalogScreen(),
    );
  }
}

final class _ComponentCatalogScreen extends StatelessWidget {
  const _ComponentCatalogScreen();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Card(
          child: SizedBox(
            width: 48,
            height: 48,
            child: DecoratedBox(
              decoration: BoxDecoration(color: colorScheme.primary),
            ),
          ),
        ),
      ),
    );
  }
}
