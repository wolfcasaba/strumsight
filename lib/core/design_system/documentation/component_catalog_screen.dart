import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../foundation/app_failure.dart';
import '../components/actions/ss_button.dart';
import '../components/actions/ss_icon_button.dart';
import '../components/ai/ss_model_status_card.dart';
import '../components/ai/ss_provenance_badge.dart';
import '../components/cards/ss_coach_action_card.dart';
import '../components/cards/ss_content_card.dart';
import '../components/cards/ss_insight_card.dart';
import '../components/cards/ss_metric_card.dart';
import '../components/feedback/failure_presentation.dart';
import '../components/feedback/ss_async_state.dart';
import '../components/feedback/ss_empty_state.dart';
import '../components/feedback/ss_failure_state.dart';
import '../components/feedback/ss_permission_state.dart';
import '../components/feedback/ss_status_badge.dart';
import '../components/inputs/ss_choice.dart';
import '../components/inputs/ss_switch_row.dart';
import '../components/inputs/ss_text_field.dart';
import '../components/inputs/ss_validation_summary.dart';
import '../components/inputs/ss_value_slider.dart';
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
                    const SizedBox(height: SsSpacing.space4),
                    const _ActionsAndFormsShowcase(),
                    const SizedBox(height: SsSpacing.space4),
                    const _CardsAndStatusShowcase(),
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

/// Demonstrates the Ch13 Kör 11 action/input state matrix — button
/// variants, an icon button, a labelled text field, a full-row switch, a
/// segmented choice, a tempo slider paired with its exact numeric field, and
/// a validation summary.
///
/// English-only for the same reason as [_AsyncFeedbackShowcase] (D7): the
/// catalog is a dev-only surface, [lookupAppLocalizations] resolves the
/// validation summary's generic copy without depending on a
/// `Localizations` ancestor.
final class _ActionsAndFormsShowcase extends StatelessWidget {
  const _ActionsAndFormsShowcase();

  @override
  Widget build(BuildContext context) {
    final l10n = lookupAppLocalizations(const Locale('en'));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: SsSpacing.space2,
          runSpacing: SsSpacing.space2,
          children: [
            SsButton(label: 'Save changes', onPressed: () {}),
            SsButton(
              label: 'Delete song',
              variant: SsButtonVariant.destructive,
              destructiveSemanticHint: 'This cannot be undone',
              onPressed: () {},
            ),
            SsIconButton(
              iconName: 'close',
              semanticLabel: 'Close',
              tooltip: 'Close',
              onPressed: () {},
            ),
          ],
        ),
        const SizedBox(height: SsSpacing.space2),
        const SsTextField(label: 'Song title'),
        const SizedBox(height: SsSpacing.space2),
        SsSwitchRow(label: 'Metronome click', value: true, onChanged: (_) {}),
        const SizedBox(height: SsSpacing.space2),
        SsChoice<String>(
          options: const [
            SsChoiceOption(value: 'up', label: 'Up'),
            SsChoiceOption(value: 'down', label: 'Down'),
          ],
          value: 'up',
          onChanged: (_) {},
        ),
        const SizedBox(height: SsSpacing.space2),
        SsValueSlider(
          label: 'Tempo',
          value: 120,
          min: 40,
          max: 220,
          unitLabel: 'BPM',
          onChanged: (_) {},
        ),
        const SizedBox(height: SsSpacing.space2),
        SsValidationSummary(
          l10n: l10n,
          issues: const [
            SsValidationIssue(
              fieldLabel: 'Song title',
              message: 'Song title is required',
            ),
          ],
        ),
      ],
    );
  }
}

/// Demonstrates the Ch13 Kör 12 card/badge/status matrix — the metric,
/// insight, coach-action, general-content, and model-status cards, plus the
/// provenance and status badges (ADR 0278). No skeleton demo and no extra
/// `SsCard`/`DecoratedBox` here (§0.0/D3 — the catalog's exact-count guard
/// already owns the tree's one `SsCard` and one `DecoratedBox`).
///
/// English-only for the same reason as the other showcases (D7).
final class _CardsAndStatusShowcase extends StatelessWidget {
  const _CardsAndStatusShowcase();

  @override
  Widget build(BuildContext context) {
    final l10n = lookupAppLocalizations(const Locale('en'));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: SsSpacing.space2,
          runSpacing: SsSpacing.space2,
          children: [
            const SsMetricCard(
              label: 'Practice streak',
              value: 12,
              unit: 'days',
            ),
            const SsMetricCard(
              label: 'Accuracy',
              value: 87,
              unit: '%',
              density: SsCardDensity.compact,
            ),
          ],
        ),
        const SizedBox(height: SsSpacing.space2),
        SsInsightCard(
          l10n: l10n,
          title: 'Your G-to-C transition is slowing you down',
          message: 'Three of your last five sessions paused there.',
          provenance: SsProvenanceKind.local,
          action: SsCardAction(label: 'Practice this', onPressed: () {}),
        ),
        const SizedBox(height: SsSpacing.space2),
        SsCoachActionCard(
          title: 'Ready for a tempo check?',
          message: 'Your strum timing has been steady for a week.',
          actionLabel: 'Start tempo check',
          onAction: () {},
          onDismiss: () {},
          dismissSemanticLabel: 'Dismiss suggestion',
        ),
        const SizedBox(height: SsSpacing.space2),
        SsContentCard(
          title: 'Setlist synced',
          message: 'Your Friday setlist is ready offline.',
          icon: Icons.library_music_outlined,
          actions: [
            SsCardAction(label: 'Open', onPressed: () {}),
            SsCardAction(label: 'Share', onPressed: () {}),
          ],
        ),
        const SizedBox(height: SsSpacing.space2),
        SsModelStatusCard(
          l10n: l10n,
          title: 'Chord detector',
          message: 'Running fully on this device.',
          provenance: SsProvenanceKind.local,
          statusBadges: const [
            SsStatusBadgeKind.offline,
            SsStatusBadgeKind.confidenceHigh,
          ],
        ),
        const SizedBox(height: SsSpacing.space2),
        Wrap(
          spacing: SsSpacing.space3,
          runSpacing: SsSpacing.space2,
          children: [
            SsProvenanceBadge(l10n: l10n, kind: SsProvenanceKind.local),
            SsProvenanceBadge(l10n: l10n, kind: SsProvenanceKind.cloud),
            SsStatusBadge(l10n: l10n, kind: SsStatusBadgeKind.offline),
            SsStatusBadge(l10n: l10n, kind: SsStatusBadgeKind.syncPending),
            SsStatusBadge(l10n: l10n, kind: SsStatusBadgeKind.confidenceHigh),
            SsStatusBadge(l10n: l10n, kind: SsStatusBadgeKind.confidenceMedium),
            SsStatusBadge(l10n: l10n, kind: SsStatusBadgeKind.confidenceLow),
          ],
        ),
      ],
    );
  }
}
