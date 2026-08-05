/// Tutor Chat banners (E04-R18 §5.3).
///
/// Every banner kind renders an icon, a localized title + body, and a
/// unique semantics label so the screen-reader announces each banner
/// separately. The four "real" banner kinds (offline, consent,
/// rateLimit, error) plus the user-cancelled banner all have their own
/// ARB key — the chat screen test asserts on the four distinct
/// semantics labels per brief §6.
///
/// The widget is purely presentational; the banner list comes from
/// [TutorChatController.banners] via the providers layer.
library;

import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../providers/tutor_providers.dart';

/// A single tutor banner — one icon, one title, one body, one
/// semantics label. The widget is `const`-friendly: the controller
/// never reaches into it, so the parent builds fresh instances per
/// banner kind and the test can find each by its own semantics label.
class TutorBanner extends StatelessWidget {
  const TutorBanner({
    super.key,
    required this.kind,
    this.onRetry,
    this.onConsent,
  });

  final TutorBannerKind kind;

  /// Optional retry callback for the error banner.
  final VoidCallback? onRetry;

  /// Optional callback that opens the consent screen.
  final VoidCallback? onConsent;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final spec = _specFor(kind, l10n, theme);
    return Semantics(
      container: true,
      label: spec.semanticsLabel,
      liveRegion: true,
      child: Material(
        color: spec.background,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(spec.icon, color: spec.foreground),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      spec.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: spec.foreground,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      spec.body,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: spec.foreground,
                      ),
                    ),
                    if (spec.actionLabel != null &&
                        (spec.action == BannerAction.retry ||
                            spec.action == BannerAction.consent)) ...<Widget>[
                      const SizedBox(height: 8),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton(
                          onPressed: spec.action == BannerAction.retry
                              ? onRetry
                              : onConsent,
                          child: Text(spec.actionLabel!),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum BannerAction { none, retry, consent }

class _BannerSpec {
  const _BannerSpec({
    required this.icon,
    required this.title,
    required this.body,
    required this.semanticsLabel,
    required this.background,
    required this.foreground,
    this.actionLabel,
    this.action = BannerAction.none,
  });

  final IconData icon;
  final String title;
  final String body;
  final String semanticsLabel;
  final Color background;
  final Color foreground;
  final String? actionLabel;
  final BannerAction action;
}

_BannerSpec _specFor(
  TutorBannerKind kind,
  AppLocalizations l10n,
  ThemeData theme,
) {
  final scheme = theme.colorScheme;
  switch (kind) {
    case TutorBannerKind.offline:
      return _BannerSpec(
        icon: Icons.wifi_off,
        title: l10n.aiTutorBannerOfflineTitle,
        body: l10n.aiTutorBannerOfflineBody,
        semanticsLabel: l10n.aiTutorBannerOfflineSemantics,
        background: scheme.errorContainer.withValues(alpha: 0.5),
        foreground: scheme.onErrorContainer,
      );
    case TutorBannerKind.consent:
      return _BannerSpec(
        icon: Icons.shield_outlined,
        title: l10n.aiTutorBannerConsentTitle,
        body: l10n.aiTutorBannerConsentBody,
        semanticsLabel: l10n.aiTutorBannerConsentSemantics,
        background: scheme.tertiaryContainer.withValues(alpha: 0.5),
        foreground: scheme.onTertiaryContainer,
        actionLabel: l10n.aiTutorBannerConsentAction,
        action: BannerAction.consent,
      );
    case TutorBannerKind.rateLimit:
      return _BannerSpec(
        icon: Icons.hourglass_bottom,
        title: l10n.aiTutorBannerRateLimitTitle,
        body: l10n.aiTutorBannerRateLimitBody,
        semanticsLabel: l10n.aiTutorBannerRateLimitSemantics,
        background: scheme.secondaryContainer.withValues(alpha: 0.5),
        foreground: scheme.onSecondaryContainer,
      );
    case TutorBannerKind.error:
      return _BannerSpec(
        icon: Icons.error_outline,
        title: l10n.aiTutorBannerErrorTitle,
        body: l10n.aiTutorBannerErrorBody,
        semanticsLabel: l10n.aiTutorBannerErrorSemantics,
        background: scheme.errorContainer.withValues(alpha: 0.5),
        foreground: scheme.onErrorContainer,
        actionLabel: l10n.aiTutorChatRetry,
        action: BannerAction.retry,
      );
    case TutorBannerKind.cancelled:
      return _BannerSpec(
        icon: Icons.cancel_outlined,
        title: l10n.aiTutorBannerCancelledTitle,
        body: l10n.aiTutorBannerCancelledBody,
        semanticsLabel: l10n.aiTutorBannerCancelledSemantics,
        background: scheme.surfaceContainerHighest,
        foreground: scheme.onSurface,
      );
  }
}
