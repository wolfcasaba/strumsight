import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../foundations/ss_colors.dart';
import '../themes/ss_dark_theme.dart';
import '../themes/ss_high_contrast_theme.dart';
import '../themes/ss_light_theme.dart';

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

final class _ComponentCatalogScreen extends StatefulWidget {
  const _ComponentCatalogScreen();

  @override
  State<_ComponentCatalogScreen> createState() =>
      _ComponentCatalogScreenState();
}

enum _CatalogTheme { dark, light, highContrast }

final class _ComponentCatalogScreenState
    extends State<_ComponentCatalogScreen> {
  var _selectedTheme = _CatalogTheme.dark;

  @override
  Widget build(BuildContext context) {
    final theme = switch (_selectedTheme) {
      _CatalogTheme.dark => SsDarkTheme.data(),
      _CatalogTheme.light => SsLightTheme.data(),
      _CatalogTheme.highContrast => SsHighContrastTheme.data(),
    };
    final colors = theme.extension<SsColorScheme>()!;

    return Theme(
      data: theme,
      child: Scaffold(
        body: Center(
          child: Card(
            child: DecoratedBox(
              decoration: BoxDecoration(color: colors.surface),
              child: SizedBox(
                width: 192,
                height: 96,
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _themeButton(
                          icon: Icons.dark_mode_outlined,
                          theme: _CatalogTheme.dark,
                        ),
                        _themeButton(
                          icon: Icons.light_mode_outlined,
                          theme: _CatalogTheme.light,
                        ),
                        _themeButton(
                          icon: Icons.contrast_outlined,
                          theme: _CatalogTheme.highContrast,
                        ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        SsStatusMarker(
                          kind: SsStatusMarkerKind.confidence,
                          color: colors.confidenceLow,
                        ),
                        SsStatusMarker(
                          kind: SsStatusMarkerKind.offline,
                          color: colors.offline,
                        ),
                        SsStatusMarker(
                          kind: SsStatusMarkerKind.localAi,
                          color: colors.localAi,
                        ),
                        SsStatusMarker(
                          kind: SsStatusMarkerKind.cloudAi,
                          color: colors.cloudAi,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _themeButton({required IconData icon, required _CatalogTheme theme}) {
    return IconButton(
      onPressed: () => setState(() => _selectedTheme = theme),
      icon: Icon(icon),
    );
  }
}
