import 'package:flutter/material.dart';

import 'package:strumsight/core/design_system/public.dart';
import 'package:strumsight/l10n/app_localizations.dart';

/// The visible placeholder a [ModerationState.removed] post or comment gets
/// instead of its real body (brief §5.6 / ADR 0291 §6, A7).
///
/// [ModerationState.removed] is a read-side policy trigger, not a display
/// hint (`moderation_state.dart` doc comment) — the backend is documented to
/// substitute a placeholder row before this ever reaches the client, but
/// nothing in the presentation layer previously defended against a removed
/// row surfacing here directly. This widget is that defence: the
/// conversation stays legible instead of a row silently vanishing.
final class CommunityModerationPlaceholder extends StatelessWidget {
  const CommunityModerationPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return SsSurface(
      child: Padding(
        padding: const EdgeInsets.all(SsSpacing.space4),
        child: Row(
          children: <Widget>[
            Icon(
              Icons.block_flipped,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: SsSpacing.space2),
            Expanded(
              child: Text(
                l10n.communityModerationRemovedPlaceholder,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
