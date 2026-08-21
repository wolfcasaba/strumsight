import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

abstract final class ComponentCatalog {
  static const bool isCompileTimeEnabled = bool.fromEnvironment(
    'STRUMSIGHT_COMPONENT_CATALOG',
    defaultValue: false,
  );

  static Route<void>? createRoute() {
    return _createRoute(
      catalogEnabled: isCompileTimeEnabled,
      debugBuild: kDebugMode,
    );
  }

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
      builder: (_) => const ComponentCatalogScreen(),
    );
  }
}

final class ComponentCatalogScreen extends StatelessWidget {
  const ComponentCatalogScreen({super.key});

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
