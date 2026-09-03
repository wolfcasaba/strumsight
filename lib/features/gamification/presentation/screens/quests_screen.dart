import 'package:flutter/material.dart';

import '../../../../core/design_system/public.dart';
import '../../application/daily_challenge_service.dart'
    show DailyChallengeInstance;
import '../../domain/quests/quest_definition.dart';
import '../../domain/quests/quest_progress.dart';
import '../widgets/challenge_card.dart';
import '../widgets/gamification_theme_scope.dart';
import '../widgets/quest_card.dart';
import '../../../../l10n/app_localizations.dart';

/// Caller-supplied projection facts for one rendered quest. The view never
/// derives the target or completed units itself (ADR 0290 §2).
class QuestViewProjection {
  QuestViewProjection({
    required this.definition,
    required this.progress,
    required this.targetUnits,
    required this.completedUnits,
    required this.contentAvailable,
    this.sourcePlanLabel,
  }) : assert(targetUnits >= 1, 'targetUnits must be positive'),
       assert(completedUnits >= 0, 'completedUnits must not be negative');

  final QuestDefinition definition;
  final QuestProgress progress;
  final int targetUnits;
  final int completedUnits;
  final bool contentAvailable;
  final String? sourcePlanLabel;
}

/// Daily & weekly quest overview. The screen owns no policy, repository, or
/// navigation — every fact is fed by the caller and every CTA emits a typed
/// [QuestRouteAction] (brief §5.3, route registration lives in round 30).
class QuestsScreen extends StatelessWidget {
  const QuestsScreen({
    super.key,
    required this.dailyChallengeTitle,
    this.dailyChallenge,
    required this.dailyChallengeAvailable,
    required this.dailyQuests,
    required this.weeklyQuests,
    required this.onAction,
    required this.now,
    this.showOfflineBanner = true,
  });

  /// Caller-supplied title for the daily challenge section (e.g.
  /// `l10n.challengeDailyTitle`).
  final String dailyChallengeTitle;

  /// Optional active daily challenge instance.
  final DailyChallengeInstance? dailyChallenge;

  /// Whether the daily challenge's underlying content is installed.
  final bool dailyChallengeAvailable;

  /// Caller-fed daily quests in display order.
  final List<QuestViewProjection> dailyQuests;

  /// Caller-fed weekly quests in display order.
  final List<QuestViewProjection> weeklyQuests;

  /// Outer callback translating typed [QuestRouteAction] into navigation.
  final ValueChanged<QuestRouteAction> onAction;

  /// Caller-fed clock for deterministic expiry rendering.
  final DateTime now;

  /// Whether the screen renders the offline-friendly banner. Always on by
  /// default because the screen has zero network dependency (brief A6).
  final bool showOfflineBanner;

  bool get _isEmpty =>
      dailyChallenge == null && dailyQuests.isEmpty && weeklyQuests.isEmpty;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return GamificationThemeScope(
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.questsScreenTitle)),
        body: SafeArea(
          child: _isEmpty
              ? const _EmptyQuestsState()
              : ListView(
                  key: const Key('quests-screen-list'),
                  padding: const EdgeInsets.fromLTRB(
                    SsSpacing.space5,
                    SsSpacing.space3,
                    SsSpacing.space5,
                    SsSpacing.space6,
                  ),
                  children: [
                    if (showOfflineBanner) const _OfflineBanner(),
                    if (dailyChallenge != null) ...[
                      _SectionHeader(
                        title: dailyChallengeTitle,
                        keyName: 'quests-daily-section-title',
                      ),
                      const SizedBox(height: SsSpacing.space2),
                      ChallengeCard(
                        title: dailyChallengeTitle,
                        instance: dailyChallenge!,
                        contentAvailable: dailyChallengeAvailable,
                        onAction: onAction,
                      ),
                      const SizedBox(height: SsSpacing.space4),
                    ],
                    if (dailyQuests.isNotEmpty) ...[
                      _SectionHeader(
                        title: l10n.questsDailySectionTitle,
                        keyName: 'quests-daily-quests-title',
                      ),
                      const SizedBox(height: SsSpacing.space2),
                      for (final projection in dailyQuests) ...[
                        _buildQuestCard(context, projection),
                        const SizedBox(height: SsSpacing.space3),
                      ],
                    ],
                    if (weeklyQuests.isNotEmpty) ...[
                      _SectionHeader(
                        title: l10n.questsWeeklySectionTitle,
                        keyName: 'quests-weekly-quests-title',
                      ),
                      const SizedBox(height: SsSpacing.space2),
                      for (final projection in weeklyQuests) ...[
                        _buildQuestCard(context, projection),
                        const SizedBox(height: SsSpacing.space3),
                      ],
                    ],
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildQuestCard(BuildContext context, QuestViewProjection projection) {
    final title = _projectTitle(projection);
    return QuestCard(
      key: ValueKey<String>('quest-card-${projection.definition.id}'),
      title: title,
      definition: projection.definition,
      progress: projection.progress,
      targetUnits: projection.targetUnits,
      completedUnits: projection.completedUnits,
      contentAvailable: projection.contentAvailable,
      sourcePlanLabel: projection.sourcePlanLabel,
      onAction: onAction,
      now: now,
    );
  }

  String _projectTitle(QuestViewProjection projection) {
    final label = projection.sourcePlanLabel;
    if (label != null && label.trim().isNotEmpty) {
      return label;
    }
    return projection.definition.id;
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.keyName});

  final String title;
  final String keyName;

  @override
  Widget build(BuildContext context) {
    final typography = Theme.of(context).extension<SsTypography>()!;
    return Text(title, key: Key(keyName), style: typography.titleLarge);
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final typography = Theme.of(context).extension<SsTypography>()!;
    return Padding(
      padding: const EdgeInsets.only(bottom: SsSpacing.space4),
      child: SsSurface(
        key: const Key('quests-offline-banner'),
        child: Padding(
          padding: const EdgeInsets.all(SsSpacing.space3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.questsOfflineBanner, style: typography.titleMedium),
              const SizedBox(height: SsSpacing.space1),
              Text(l10n.questsOfflineBody, style: typography.bodyMedium),
            ],
          ),
        ),
      ),
    );
  }
}

// Screen-local, token-styled — NOT SsEmptyState: a brand-new user with no
// quests yet has no real next action to offer from this screen (quests are
// generated by the caller, not created here), so inventing a CTA to satisfy
// SsEmptyState's required action would misrepresent the screen (brief
// §0.0.A/R7, same exception class as E15-R06/R07's empty states).
class _EmptyQuestsState extends StatelessWidget {
  const _EmptyQuestsState();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
    // SingleChildScrollView, not a bare Center — at 200%+ text scale on a
    // phone-width viewport the message can outgrow the screen height, and an
    // unscrollable Center would overflow (§0.0.A/R5/R6, same pattern fixed
    // for achievement_detail's _notFound/_hidden states — E15-R08 review B1).
    return Center(
      key: const Key('quests-empty-state'),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: SsSpacing.space8,
            vertical: SsSpacing.space12,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                l10n.questsEmptyTitle,
                style: typography.titleLarge.copyWith(
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: SsSpacing.space2),
              Text(
                l10n.questsEmptyBody,
                textAlign: TextAlign.center,
                style: typography.bodyMedium.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
