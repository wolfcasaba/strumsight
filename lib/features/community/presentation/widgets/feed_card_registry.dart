/// Feed card registry (E09-R14, brief §3 / §5.3 / §6 A5).
///
/// Maps each Community post + its [ShareArtifact] to a card widget. The
/// registry is **exhaustive over the seven Kör 10 artifact subtypes** plus
/// a fallback card for unknown / future artifact types.
///
/// **Why a registry (not a switch at every call-site, brief §5.3):** every
/// post on the feed must render through one funnel so a future, yet-unknown
/// artifact type surfaces a graceful "tartalom nem jeleníthető meg" card
/// instead of crashing the feed (A5). The exhaustiveness is enforced by the
/// `switch` on `ShareArtifactType` — adding a new subtype without a matching
/// card case is a compile-time error.
///
/// **Why no autoplay / no media widget here (A3, brief §5.1):** the cards
/// are inert on load — no video, no audio, no carousel auto-advance. Media
/// playback is a future round's job and will land behind an explicit user
/// interaction (tap-to-play); the registry never embeds a media widget that
/// starts on first frame. The artifact payload is rendered as plain text /
/// icons — the user reads the post first, and chooses to open the source.
///
/// **i18n (F1):** every user-facing string routes through
/// `AppLocalizations.of(context)`; per-card titles / metric lines / reward
/// lines interpolate values via the ARB ICU placeholders (numbers,
/// `DateTime.toIso8601String()`, pattern strings, etc.).
library;

import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../domain/entities/community_post.dart';
import '../../domain/entities/share_artifact.dart';
import '../../domain/policies/community_audience.dart';

/// The card-registry entry-point.
///
/// Renders [post] using the card matching the artifact's [ShareArtifactType].
/// Unknown artifact types fall through to [_FallbackCard] (A5).
class FeedCard extends StatelessWidget {
  const FeedCard({super.key, required this.post});

  /// The post this card renders. The card reads only the post's public
  /// fields — it never mutates the controller or the repository.
  final CommunityPost post;

  @override
  Widget build(BuildContext context) {
    final artifact = post.artifact;
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _CardHeader(post: post),
            const SizedBox(height: 8),
            if (post.body != null && post.body!.isNotEmpty) ...<Widget>[
              Text(post.body!, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 8),
            ],
            _artifactBody(context: context, post: post, artifact: artifact),
            const SizedBox(height: 8),
            _CardCounts(post: post),
          ],
        ),
      ),
    );
  }

  /// Route the artifact to its concrete card. The `switch` is exhaustive
  /// over the Kör 10 sealed hierarchy; an unknown runtime type falls
  /// through to [_FallbackCard] (A5).
  Widget _artifactBody({
    required BuildContext context,
    required CommunityPost post,
    required CommunityShareArtifact artifact,
  }) {
    if (artifact is UnfilledCommunityShareArtifact) {
      return const _FallbackCard(reason: _FallbackReason.unfilled);
    }
    if (artifact is ShareArtifact) {
      // The `switch` over the Kör 10 sealed hierarchy's type
      // discriminator narrows the runtime type — Dart's exhaustive
      // pattern matching checks every concrete subclass at compile
      // time, so a future concrete subtype added to `ShareArtifact`
      // without a matching card here is a compile error.
      switch (artifact) {
        case PracticeSummaryArtifact():
          return _PracticeSummaryCard(artifact: artifact);
        case SongResultArtifact():
          return _SongResultCard(artifact: artifact);
        case OriginalProgressionArtifact():
          return _OriginalProgressionCard(artifact: artifact);
        case PlanTemplateArtifact():
          return _PlanTemplateCard(artifact: artifact);
        case AnalysisImprovementArtifact():
          return _AnalysisImprovementCard(artifact: artifact);
        case AchievementArtifact():
          return _AchievementCard(artifact: artifact);
        case ChallengeArtifact():
          return _ChallengeCard(artifact: artifact);
      }
    }
    return const _FallbackCard(reason: _FallbackReason.unknown);
  }
}

// ---------------------------------------------------------------------------
// Card header / counts — shared across artifact types
// ---------------------------------------------------------------------------

class _CardHeader extends StatelessWidget {
  const _CardHeader({required this.post});
  final CommunityPost post;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: <Widget>[
        CircleAvatar(child: Text(_initials(post.authorId.value))),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                post.authorId.value,
                style: theme.textTheme.titleSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                _formatTimestamp(post.createdAt),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
        _AudienceBadge(audience: post.audience),
      ],
    );
  }

  String _initials(String id) {
    if (id.isEmpty) return '?';
    return id.substring(0, 1).toUpperCase();
  }

  String _formatTimestamp(DateTime ts) {
    // Stable, locale-neutral render — the card does not own i18n labels
    // for the timestamp itself (future round); this keeps the card
    // predictable for the widget test.
    return ts.toIso8601String();
  }
}

class _AudienceBadge extends StatelessWidget {
  const _AudienceBadge({required this.audience});

  // F3 — typed `CommunityAudience` instead of `dynamic`. The single
  // call-site (`_CardHeader`) always passes a typed value, and the
  // compile-time check guarantees a future call-site mistake surfaces
  // loudly instead of degrading silently to `'public'`.
  final CommunityAudience audience;

  @override
  Widget build(BuildContext context) {
    final label = audience.wireValue;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

class _CardCounts extends StatelessWidget {
  const _CardCounts({required this.post});
  final CommunityPost post;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final counts = post.counts;
    return Row(
      children: <Widget>[
        Icon(Icons.favorite_border, size: 16, color: theme.iconTheme.color),
        const SizedBox(width: 4),
        Text(counts.reactionCount.toString(), style: theme.textTheme.bodySmall),
        const SizedBox(width: 16),
        Icon(
          Icons.mode_comment_outlined,
          size: 16,
          color: theme.iconTheme.color,
        ),
        const SizedBox(width: 4),
        Text(counts.commentCount.toString(), style: theme.textTheme.bodySmall),
        const SizedBox(width: 16),
        Icon(Icons.bookmark_border, size: 16, color: theme.iconTheme.color),
        const SizedBox(width: 4),
        Text(counts.bookmarkCount.toString(), style: theme.textTheme.bodySmall),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Concrete artifact cards
// ---------------------------------------------------------------------------

abstract class _ArtifactCard<T extends ShareArtifact> extends StatelessWidget {
  const _ArtifactCard({required this.artifact});
  final T artifact;
}

class _PracticeSummaryCard extends _ArtifactCard<PracticeSummaryArtifact> {
  const _PracticeSummaryCard({required super.artifact});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = AppLocalizations.of(context);
    final a = artifact;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          localizations.feedCardPracticeSummaryTitle,
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        Text(
          localizations.feedCardPracticeSummaryBody(
            a.activeSeconds,
            a.pausedSeconds,
            a.attemptCount,
          ),
          style: theme.textTheme.bodySmall,
        ),
        if (a.bestScore != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              localizations.feedCardPracticeSummaryBestScore(
                (a.bestScore! * 100).round(),
              ),
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

class _SongResultCard extends _ArtifactCard<SongResultArtifact> {
  const _SongResultCard({required super.artifact});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = AppLocalizations.of(context);
    final a = artifact;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(a.songName, style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          localizations.feedCardSongBpmBeats(
            a.bpm,
            a.beatsPerBar,
            a.chords.join(' → '),
          ),
          style: theme.textTheme.bodySmall,
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            localizations.feedCardStrumPattern(a.strumPattern),
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _OriginalProgressionCard
    extends _ArtifactCard<OriginalProgressionArtifact> {
  const _OriginalProgressionCard({required super.artifact});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = AppLocalizations.of(context);
    final a = artifact;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          localizations.feedCardOriginalProgressionTitle(a.songName),
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        Text(
          localizations.feedCardSongBpmBeats(
            a.bpm,
            a.beatsPerBar,
            a.chords.join(' → '),
          ),
          style: theme.textTheme.bodySmall,
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            localizations.feedCardStrumPattern(a.strumPattern),
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _PlanTemplateCard extends _ArtifactCard<PlanTemplateArtifact> {
  const _PlanTemplateCard({required super.artifact});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = AppLocalizations.of(context);
    final a = artifact;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          localizations.feedCardPlanTemplateTitle(a.songName),
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        Text(
          localizations.feedCardSongBpmBeats(
            a.bpm,
            a.beatsPerBar,
            a.chords.join(' → '),
          ),
          style: theme.textTheme.bodySmall,
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            localizations.feedCardStrumPattern(a.strumPattern),
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _AnalysisImprovementCard
    extends _ArtifactCard<AnalysisImprovementArtifact> {
  const _AnalysisImprovementCard({required super.artifact});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = AppLocalizations.of(context);
    final a = artifact;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          localizations.feedCardAnalysisImprovementTitle,
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        for (final m in a.metrics)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              localizations.feedCardAnalysisImprovementMetric(
                m.metricId,
                m.directionCode,
                m.beforeValue?.toString() ?? '-',
                m.afterValue?.toString() ?? '-',
              ),
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

class _AchievementCard extends _ArtifactCard<AchievementArtifact> {
  const _AchievementCard({required super.artifact});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = AppLocalizations.of(context);
    final a = artifact;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          localizations.feedCardAchievementUnlocked,
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        Text(
          localizations.feedCardAchievementCatalogVersion(
            a.achievementId,
            a.categoryCode,
            a.catalogVersion,
          ),
          style: theme.textTheme.bodySmall,
        ),
        if (a.completedAt != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              localizations.feedCardAchievementCompletedAt(
                a.completedAt!.toIso8601String(),
              ),
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

class _ChallengeCard extends _ArtifactCard<ChallengeArtifact> {
  const _ChallengeCard({required super.artifact});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = AppLocalizations.of(context);
    final a = artifact;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          localizations.feedCardChallengeTitle(a.challengeName),
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        Text(
          localizations.feedCardChallengeReward(
            a.challengeTypeCode,
            a.rewardStatusCode,
          ),
          style: theme.textTheme.bodySmall,
        ),
        if (a.rewardXp != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              localizations.feedCardChallengeXp(a.rewardXp!),
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Fallback card — unknown / future artifact types (A5)
// ---------------------------------------------------------------------------

enum _FallbackReason { unfilled, unknown }

class _FallbackCard extends StatelessWidget {
  const _FallbackCard({required this.reason});
  final _FallbackReason reason;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = AppLocalizations.of(context);
    final text = reason == _FallbackReason.unfilled
        ? localizations.feedCardFallbackUnfilled
        : localizations.feedCardFallbackUnknown;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.info_outline, color: theme.iconTheme.color),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}
