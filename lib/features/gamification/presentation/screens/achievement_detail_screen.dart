import 'package:flutter/material.dart';
import 'package:strumsight/core/design_system/public.dart';
import 'package:strumsight/features/gamification/domain/achievements/achievement_definition.dart';
import 'package:strumsight/features/gamification/domain/achievements/achievement_progress.dart';
import 'package:strumsight/features/gamification/presentation/widgets/achievement_tile.dart';
import 'package:strumsight/features/gamification/presentation/widgets/gamification_theme_scope.dart';
import 'package:strumsight/l10n/app_localizations.dart';

enum AchievementEvidenceReasonCode {
  measuredProgress,
  completionRecorded,
  unknown,
}

final class AchievementEvidence {
  AchievementEvidence({
    required this.reason,
    required this.current,
    required this.target,
  }) {
    if (!current.isFinite || current < 0) {
      throw ArgumentError.value(
        current,
        'current',
        'must be finite and nonnegative',
      );
    }
    if (!target.isFinite || target <= 0) {
      throw ArgumentError.value(
        target,
        'target',
        'must be finite and positive',
      );
    }
  }

  final AchievementEvidenceReasonCode reason;
  final num current;
  final num target;
}

class AchievementDetailScreen extends StatelessWidget {
  const AchievementDetailScreen({
    super.key,
    required this.achievementId,
    required this.definitions,
    required this.progressByAchievement,
    this.evidence,
  });

  final String achievementId;
  final List<AchievementDefinition> definitions;
  final Map<String, AchievementProgress> progressByAchievement;
  final AchievementEvidence? evidence;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final definition = _definitionForId();
    if (definition == null) return _notFound(context, l10n);

    final progress = progressByAchievement[definition.id];
    if (definition.hidden && !achievementIsUnlocked(progress)) {
      return _hidden(context, l10n);
    }

    final content = localizedAchievementContent(l10n, definition);
    if (content == null) return _notFound(context, l10n);
    final percent = achievementPercent(progress);
    final completedAt = progress?.completedAt;
    final formattedCompletedAt = completedAt == null
        ? null
        : MaterialLocalizations.of(context).formatMediumDate(completedAt);
    final completion = formattedCompletedAt == null
        ? null
        : l10n.achievementUnlockedOn(formattedCompletedAt);
    return GamificationThemeScope(
      child: Builder(
        builder: (context) {
          // A fresh `context` from inside the wrapper's subtree — the
          // outer `build(context)` parameter sits ABOVE the merged theme,
          // so `Theme.of(context).extension<SsTypography>()!` on it would
          // null-check against the ambient (non-DS) theme.
          final typography = Theme.of(context).extension<SsTypography>()!;
          return Scaffold(
            appBar: AppBar(title: Text(l10n.achievementsTitle)),
            body: SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                children: [
                  Semantics(
                    container: true,
                    label: formattedCompletedAt == null
                        ? l10n.achievementTileSemanticsInProgress(
                            achievementSemanticsDescription(
                              content.accessibilityDescription,
                            ),
                            percent,
                          )
                        : l10n.achievementTileSemanticsUnlocked(
                            achievementSemanticsDescription(
                              content.accessibilityDescription,
                            ),
                            percent,
                            formattedCompletedAt,
                          ),
                    child: ExcludeSemantics(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(content.title, style: typography.headlineMedium),
                          const SizedBox(height: SsSpacing.space2),
                          Text(
                            content.description,
                            style: typography.bodyMedium,
                          ),
                          const SizedBox(height: SsSpacing.space4),
                          Text(
                            l10n.achievementProgress(percent),
                            style: typography.bodyMedium,
                          ),
                          if (completion != null) ...[
                            const SizedBox(height: SsSpacing.space1),
                            Text(completion, style: typography.bodyMedium),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (evidence != null) ...[
                    const SizedBox(height: SsSpacing.space6),
                    SsCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            l10n.achievementEvidenceTitle,
                            style: typography.titleMedium,
                          ),
                          const SizedBox(height: SsSpacing.space2),
                          Text(
                            _evidenceText(l10n, evidence!),
                            style: typography.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  AchievementDefinition? _definitionForId() {
    for (final definition in definitions) {
      if (definition.id == achievementId) return definition;
    }
    return null;
  }

  // Screen-local, token-styled — NOT SsEmptyState: neither the not-found
  // nor the hidden state has a real next action (there is nothing else for
  // the user to do from an unresolvable/locked detail route), so inventing
  // one to satisfy SsEmptyState's required action would misrepresent the
  // screen (brief §0.0.A/R7).
  // Both states below wrap their message in a SingleChildScrollView, not a
  // bare Center — at 200%+ text scale on a phone-width viewport the
  // message can outgrow the screen height, and an unscrollable Center
  // would clip it (§0.0.A/R5/R6 — the fix applies to every instance of
  // this pattern, not just the one a probe happens to catch first).
  Widget _notFound(BuildContext context, AppLocalizations l10n) =>
      GamificationThemeScope(
        child: Scaffold(
          appBar: AppBar(title: Text(l10n.achievementsTitle)),
          body: Center(
            child: SingleChildScrollView(
              child: _TokenMessage(
                icon: Icons.search_off_outlined,
                title: l10n.achievementNotFoundTitle,
                body: l10n.achievementNotFoundBody,
              ),
            ),
          ),
        ),
      );

  Widget _hidden(BuildContext context, AppLocalizations l10n) =>
      GamificationThemeScope(
        child: Scaffold(
          appBar: AppBar(title: Text(l10n.achievementsTitle)),
          body: Center(
            child: SingleChildScrollView(
              child: _TokenMessage(
                icon: Icons.lock_outline,
                title: l10n.achievementHiddenTitle,
                body: l10n.achievementHiddenBody,
              ),
            ),
          ),
        ),
      );
}

class _TokenMessage extends StatelessWidget {
  const _TokenMessage({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
    return Padding(
      padding: const EdgeInsets.all(SsSpacing.space6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: colors.textSecondary),
          const SizedBox(height: SsSpacing.space3),
          Text(
            title,
            style: typography.titleMedium.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: SsSpacing.space1),
          Text(
            body,
            textAlign: TextAlign.center,
            style: typography.bodyMedium.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

String _evidenceText(
  AppLocalizations l10n,
  AchievementEvidence evidence,
) => switch (evidence.reason) {
  AchievementEvidenceReasonCode.measuredProgress =>
    l10n.achievementEvidenceMeasuredProgress(evidence.current, evidence.target),
  AchievementEvidenceReasonCode.completionRecorded =>
    l10n.achievementEvidenceCompletionRecorded,
  AchievementEvidenceReasonCode.unknown => l10n.achievementEvidenceUnavailable,
};
