import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../components/surfaces/ss_card.dart';
import '../components/surfaces/ss_hero_card.dart';
import '../components/surfaces/ss_surface.dart';
import '../foundations/ss_colors.dart';
import '../foundations/ss_elevation.dart';
import '../foundations/ss_motion.dart';
import '../foundations/ss_spacing.dart';
import '../motion/ss_beat_pulse.dart';
import '../motion/ss_motion_scope.dart';
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
  final Stopwatch _beatStopwatch = Stopwatch()..start();
  bool? _reduceMotionOverride;

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
        body: DecoratedBox(
          decoration: BoxDecoration(color: colors.canvas),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(SsSpacing.space4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
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
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SsSurface(
                          elevation: SsElevation.base,
                          child: const SizedBox(height: SsSpacing.space6),
                        ),
                        const SizedBox(height: SsSpacing.space2),
                        const SsCard(child: SizedBox(height: SsSpacing.space6)),
                        const SizedBox(height: SsSpacing.space2),
                        const SsHeroCard(
                          child: SizedBox(height: SsSpacing.space6),
                        ),
                        const SizedBox(height: SsSpacing.space2),
                        SsSurface(
                          elevation: SsElevation.modal,
                          child: const SizedBox(height: SsSpacing.space6),
                        ),
                      ],
                    ),
                    const SizedBox(height: SsSpacing.space4),
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
                    const SizedBox(height: SsSpacing.space4),
                    SsMotionScope(
                      appOverride: _reduceMotionOverride,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          SsBeatPulse(
                            clock: _DemoBeatClock(_beatStopwatch),
                            beatDuration: SsMotion.celebration,
                          ),
                          IconButton(
                            onPressed: _toggleBeat,
                            icon: Icon(
                              _beatStopwatch.isRunning
                                  ? Icons.pause_circle_outline
                                  : Icons.play_circle_outline,
                            ),
                          ),
                          IconButton(
                            onPressed: _cycleReduceMotionOverride,
                            icon: Icon(_reduceMotionOverrideIcon),
                          ),
                        ],
                      ),
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

  IconData get _reduceMotionOverrideIcon => switch (_reduceMotionOverride) {
    true => Icons.accessibility_new_outlined,
    false => Icons.directions_run_outlined,
    null => Icons.settings_suggest_outlined,
  };

  void _toggleBeat() {
    setState(() {
      if (_beatStopwatch.isRunning) {
        _beatStopwatch.stop();
      } else {
        _beatStopwatch.start();
      }
    });
  }

  void _cycleReduceMotionOverride() {
    setState(() {
      _reduceMotionOverride = switch (_reduceMotionOverride) {
        null => true,
        true => false,
        false => null,
      };
    });
  }

  Widget _themeButton({required IconData icon, required _CatalogTheme theme}) {
    return IconButton(
      onPressed: () => setState(() => _selectedTheme = theme),
      icon: Icon(icon),
    );
  }
}

/// Dev-only demo clock: exposes a free-running [Stopwatch]'s elapsed wall
/// time as an [SsBeatClock] position, standing in for a real playback
/// timeline in the catalog. `null` while paused, matching the "no live
/// timeline → no animation" rule (ADR 0274).
final class _DemoBeatClock implements SsBeatClock {
  const _DemoBeatClock(this._stopwatch);

  final Stopwatch _stopwatch;

  @override
  Duration? get position => _stopwatch.isRunning ? _stopwatch.elapsed : null;
}
