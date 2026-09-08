/// Community media player widget (E09-R19, ADR 0412).
///
/// Renders one of two faces depending on the media row's
/// ``processingState``:
///
/// * **pending** (``uploaded`` / ``scanning`` / ``transcoding`` /
///   ``review``) — a placeholder card that names the state and
///   never embeds an ``<audio>`` / ``<video>`` element. This is
///   the A2 acceptance cell — pending media is NEVER playable,
///   no matter how much the surrounding UI pushes for it.
///
/// * **ready** — the actual player card. The widget does not
///   include a real network-fetching player (that lands in a
///   future round — the playback-URL service issues an
///   application-level HMAC token today; a real bucket-GET
///   route is a nyitott horog, ADR 0412 §D6). The widget
///   instead renders the metadata the post-attachment round
///   will provide and exposes a tap-to-play affordance.
///
/// * **rejected** / **deleted** — the rejected / deleted
///   placeholder card. NEVER embeds an ``<audio>`` / ``<video>``
///   element (A3 — a rejected media must not render in a post).
///
/// The widget is pure (no provider dependency on the
/// upload/process pipeline state — the parent passes the
/// ``processingState`` literal). This keeps the test surface
/// trivial: a single ``CommunityMediaPlayer`` widget that
/// renders three faces deterministically.
library;

import 'package:flutter/material.dart';

import 'package:strumsight/core/design_system/public.dart';

import '../../../../l10n/app_localizations.dart';
import 'community_theme_scope.dart';

/// The processing-state literal the widget understands.
///
/// The set mirrors ``backend/app/community/models/media.py``
/// ``PROCESSING_STATE_*`` constants verbatim. The widget
/// defaults to ``uploaded`` (the Kör 19 server-side default
/// for a freshly-finalized row).
enum CommunityMediaProcessingState {
  uploaded,
  scanning,
  transcoding,
  review,
  ready,
  rejected,
  deleted,
}

/// The player surface.
///
/// Renders one of three placeholder faces, depending on the
/// passed ``processingState``. The widget never imports the
/// domain layer's media entity (the post-attachment round
/// will introduce that — today the widget is a pure
/// presentation primitive that takes the state literal
/// directly).
class CommunityMediaPlayer extends StatelessWidget {
  const CommunityMediaPlayer({
    super.key,
    required this.processingState,
    this.title,
    this.aspectRatio = 16 / 9,
    this.onTapPlay,
  });

  /// The processing state the widget renders. Drives the
  /// three faces — see class docstring.
  final CommunityMediaProcessingState processingState;

  /// Optional human-readable label (e.g. "Practice session —
  /// take 2"). The widget renders this above the placeholder
  /// or the player card when supplied. NULL by default.
  final String? title;

  /// The aspect ratio the player card uses when ``ready``.
  /// Defaults to 16:9 (video); ignored on the placeholder.
  final double aspectRatio;

  /// Optional tap handler the parent wires to the player
  /// card. The widget invokes it when the user taps the
  /// "play" affordance in the ``ready`` face. NULL → no
  /// affordance is rendered.
  final VoidCallback? onTapPlay;

  @override
  Widget build(BuildContext context) {
    return CommunityThemeScope(child: _buildFace(context));
  }

  Widget _buildFace(BuildContext context) {
    switch (processingState) {
      case CommunityMediaProcessingState.ready:
        return _ReadyCard(
          title: title,
          aspectRatio: aspectRatio,
          onTapPlay: onTapPlay,
        );
      case CommunityMediaProcessingState.rejected:
        return _RejectedCard(title: title);
      case CommunityMediaProcessingState.deleted:
        return const _DeletedCard();
      case CommunityMediaProcessingState.uploaded:
      case CommunityMediaProcessingState.scanning:
      case CommunityMediaProcessingState.transcoding:
      case CommunityMediaProcessingState.review:
        return _PendingCard(state: processingState, title: title);
    }
  }
}

/// The placeholder card for non-ready states. NEVER renders an
/// audio / video element — the A2 acceptance cell.
class _PendingCard extends StatelessWidget {
  const _PendingCard({required this.state, required this.title});

  final CommunityMediaProcessingState state;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SsSurface(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (title != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(title!, style: theme.textTheme.titleMedium),
                ),
              Row(
                children: <Widget>[
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _pendingLabel(l10n, state),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _pendingLabel(
    AppLocalizations l10n,
    CommunityMediaProcessingState state,
  ) {
    switch (state) {
      case CommunityMediaProcessingState.uploaded:
        return l10n.communityMediaPendingQueued;
      case CommunityMediaProcessingState.scanning:
        return l10n.communityMediaPendingScanning;
      case CommunityMediaProcessingState.transcoding:
        return l10n.communityMediaPendingTranscoding;
      case CommunityMediaProcessingState.review:
        return l10n.communityMediaPendingReview;
      case CommunityMediaProcessingState.ready:
        // Unreachable in the placeholder branch.
        return l10n.communityMediaStateReady;
      case CommunityMediaProcessingState.rejected:
        // Unreachable.
        return l10n.communityMediaStateRejected;
      case CommunityMediaProcessingState.deleted:
        // Unreachable.
        return l10n.communityMediaStateDeleted;
    }
  }
}

/// The placeholder card for the rejected state.
///
/// The optional [title] is the caller's localized *reason* (the
/// attachment tile maps the server's machine rejection code to a
/// sentence). Dropping it here would leave the user with the generic
/// "this attachment was rejected" body and no way to learn why —
/// and it would break the widget's documented contract, which says
/// the title is rendered above the placeholder. Absent a title the
/// card renders exactly as before (the Kör 19 call sites).
class _RejectedCard extends StatelessWidget {
  const _RejectedCard({required this.title});

  final String? title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SsSurface(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (title != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(title!, style: theme.textTheme.titleMedium),
                ),
              Text(
                AppLocalizations.of(context).communityMediaRejectedBody,
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The placeholder card for the deleted state.
class _DeletedCard extends StatelessWidget {
  const _DeletedCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SsSurface(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            AppLocalizations.of(context).communityMediaDeletedBody,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ),
    );
  }
}

/// The actual player card (the ``ready`` state). The widget
/// does NOT include a real network-fetching player today — that
/// lands in the post-attachment round + the bucket-GET-signing
/// wiring round (ADR 0412 §D6 nyitott horog). The card renders
/// the affordance the parent passes (``onTapPlay``) so a future
/// round can swap the body without touching callers.
class _ReadyCard extends StatelessWidget {
  const _ReadyCard({
    required this.title,
    required this.aspectRatio,
    required this.onTapPlay,
  });

  final String? title;
  final double aspectRatio;
  final VoidCallback? onTapPlay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SsSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (title != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(title!, style: theme.textTheme.titleMedium),
              ),
            AspectRatio(
              aspectRatio: aspectRatio,
              child: Container(
                color: theme.colorScheme.surfaceContainerHighest,
                alignment: Alignment.center,
                child: Icon(
                  Icons.play_circle_outline,
                  size: 48,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: SsButton(
                  variant: SsButtonVariant.tertiary,
                  onPressed: onTapPlay,
                  icon: Icons.play_arrow,
                  label: AppLocalizations.of(context).communityMediaPlay,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
