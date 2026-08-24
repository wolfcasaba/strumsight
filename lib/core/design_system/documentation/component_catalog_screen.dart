import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../foundation/app_failure.dart';
import '../components/feedback/failure_presentation.dart';
import '../components/feedback/ss_async_state.dart';
import '../components/feedback/ss_empty_state.dart';
import '../components/feedback/ss_failure_state.dart';
import '../components/feedback/ss_permission_state.dart';
import '../components/surfaces/ss_card.dart';
import '../components/surfaces/ss_hero_card.dart';
import '../components/surfaces/ss_surface.dart';
import '../foundations/ss_colors.dart';
import '../foundations/ss_elevation.dart';
import '../foundations/ss_spacing.dart';
import '../icons/ss_icon.dart';
import '../icons/ss_icons.dart';
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
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: SsSpacing.space2,
                      runSpacing: SsSpacing.space2,
                      children: [
                        for (final glyph in SsGuitarGlyphName.values)
                          SsIcon.decorative(
                            key: ValueKey('catalog_glyph_${glyph.name}'),
                            name: glyph.name,
                            color: colors.textPrimary,
                          ),
                      ],
                    ),
                    const SizedBox(height: SsSpacing.space4),
                    const _AsyncFeedbackShowcase(),
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

/// Demonstrates the Ch13 Kör 10 feedback state matrix — empty, failure,
/// permission, and the offline cached-content overlay (ADR 0277).
///
/// English-only: the catalog is a dev-only surface with no localized product
/// copy of its own (D7); [lookupAppLocalizations] resolves the mapping
/// without depending on a `Localizations` ancestor.
final class _AsyncFeedbackShowcase extends StatelessWidget {
  const _AsyncFeedbackShowcase();

  @override
  Widget build(BuildContext context) {
    final l10n = lookupAppLocalizations(const Locale('en'));
    final offlinePresentation = SsFailurePresentation.from(
      l10n,
      const NetworkFailure(code: FailureCode.networkUnavailable),
    );
    final permissionPresentation = SsFailurePresentation.from(
      l10n,
      const PermissionFailure(
        code: FailureCode.permissionMicrophoneDenied,
        retryable: false,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 120,
          child: SsAsyncState(
            status: SsAsyncStatus.offline,
            content: const Center(child: Text('Cached content stays visible')),
            skeleton: const Center(child: CircularProgressIndicator()),
            loadingSemanticLabel: 'Loading',
            emptyState: const SizedBox(),
            failureState: const SizedBox(),
            permissionState: const SizedBox(),
            blockedState: const SizedBox(),
            offlineBanner: const Text('You are offline'),
            syncPendingBanner: const Text('Syncing…'),
            degradedBanner: const Text('Degraded mode'),
          ),
        ),
        const SizedBox(height: SsSpacing.space2),
        SsEmptyState(
          icon: Icons.library_music_outlined,
          title: 'No songs yet',
          message: 'Add your first song to build a setlist.',
          actionLabel: 'Add a song',
          onAction: () {},
        ),
        const SizedBox(height: SsSpacing.space2),
        SsFailureState(
          presentation: offlinePresentation,
          onRetry: () {},
          onContinueOffline: () {},
        ),
        const SizedBox(height: SsSpacing.space2),
        SsPermissionState(
          kind: SsPermissionKind.microphone,
          rationale: 'StrumSight needs the microphone to hear you play.',
          consequence: 'Without it, chord detection cannot run.',
          presentation: permissionPresentation,
          onOpenSettings: () {},
        ),
      ],
    );
  }
}
