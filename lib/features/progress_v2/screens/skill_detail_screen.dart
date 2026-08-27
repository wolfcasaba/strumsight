import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../../app/routing/app_route.dart';
import '../../../core/design_system/public.dart';
import '../../../l10n/app_localizations.dart';
import '../../gamification/public.dart';
import '../domain/skill_detail_projection.dart';
import '../widgets/progress_theme_scope.dart';

/// UI-50 Skill Detail — mastery, auditable evidence, and a
/// prerequisite-respecting next-step recommendation over a caller-fed
/// [SkillDetailProjection] (§0.0.B/B7). Route-less, like
/// `ProgressDashboardScreen` (§0.0.B/B4): the SDD's
/// `/profile/progress/skills/:skillId` route does not exist on this tree.
final class SkillDetailScreen extends StatelessWidget {
  const SkillDetailScreen({
    required this.projection,
    required this.onOpenEvidence,
    required this.onStartRecommendedPractice,
    super.key,
  });

  final SkillDetailProjection projection;

  /// Called with the target `AppRoutes` constant and the evidence session's
  /// id — this screen never calls a router itself (§0.0.B/B4: route string
  /// literals are forbidden, `test/tooling/route_literal_guard_test.dart`).
  final void Function(String route, String sessionId) onOpenEvidence;
  final VoidCallback onStartRecommendedPractice;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dateFormat = DateFormat.yMMMd(
      Localizations.localeOf(context).toString(),
    );
    final hasEvidence = projection.hasEvidence;
    final statusText = hasEvidence
        ? '${(projection.ratio * 100).round()}%'
        : l10n.progressV2SkillStatusUnmeasured;
    final recommendation = projection.recommendation;
    final recommendationEligible =
        recommendation != null &&
        isRecommendationEligible(
          recommendation,
          projection.achievedMilestoneIds,
        );

    return ProgressThemeScope(
      child: Scaffold(
        appBar: AppBar(title: Text(projection.title)),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SsScoreRing(
                    state: hasEvidence
                        ? SsScoreRingState.measured
                        : SsScoreRingState.unavailable,
                    ratio: hasEvidence ? projection.ratio : null,
                    label: hasEvidence
                        ? statusText
                        : l10n.progressV2ScoreRingUnavailableGlyph,
                    semanticLabel: l10n
                        .progressV2SkillDetailMasterySemanticLabel(
                          projection.title,
                          statusText,
                        ),
                    size: 56,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      projection.description,
                      key: const Key('skill-detail-description'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SsSection(
                title: l10n.progressV2EvidenceSectionTitle,
                child: projection.evidence.isEmpty
                    ? Text(
                        l10n.progressV2EvidenceEmpty,
                        key: const Key('skill-detail-no-evidence'),
                      )
                    : SsEventList(
                        key: const Key('skill-detail-evidence-list'),
                        semanticLabel: l10n.progressV2EvidenceListSemanticLabel,
                        rows: [
                          for (final evidence in projection.evidence)
                            SsEventListRow(
                              id: evidence.sessionId,
                              label: l10n.progressV2EvidenceRowLabel(
                                _originLabel(l10n, evidence.origin),
                                dateFormat.format(evidence.observedAt),
                              ),
                              semanticLabel: l10n
                                  .progressV2EvidenceRowSemanticLabel(
                                    _originLabel(l10n, evidence.origin),
                                    dateFormat.format(evidence.observedAt),
                                  ),
                              onTap: () => onOpenEvidence(
                                AppRoutes.profileLibrarySession,
                                evidence.sessionId,
                              ),
                            ),
                        ],
                      ),
              ),
              if (recommendation != null) ...[
                const SizedBox(height: 16),
                SsSection(
                  title: l10n.progressV2RecommendationSectionTitle,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Always visible, whether or not the recommendation is
                      // eligible right now (§6/F4) — the prerequisite
                      // relationship must not only be readable on the
                      // locked branch below.
                      if (recommendation.prerequisiteMilestoneId != null) ...[
                        Text(
                          recommendationEligible
                              ? l10n.progressV2RecommendationPrerequisiteMet(
                                  recommendation.prerequisiteTitle ?? '',
                                )
                              : l10n.progressV2RecommendationPrerequisiteMissing(
                                  recommendation.prerequisiteTitle ?? '',
                                ),
                          key: const Key(
                            'skill-detail-recommendation-prerequisite',
                          ),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                      ],
                      recommendationEligible
                          ? SsCoachActionCard(
                              l10n: l10n,
                              title: recommendation.title,
                              message: recommendation.message,
                              actionLabel: l10n.progressV2RecommendationAction,
                              onAction: onStartRecommendedPractice,
                            )
                          : Text(
                              l10n.progressV2RecommendationLocked(
                                recommendation.prerequisiteTitle ?? '',
                              ),
                              key: const Key(
                                'skill-detail-recommendation-locked',
                              ),
                            ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _originLabel(
    AppLocalizations l10n,
    MasteryEvidenceOrigin origin,
  ) => switch (origin) {
    MasteryEvidenceOrigin.vision => l10n.progressV2EvidenceOriginVision,
    MasteryEvidenceOrigin.analysis => l10n.progressV2EvidenceOriginAnalysis,
    MasteryEvidenceOrigin.device => l10n.progressV2EvidenceOriginDevice,
  };
}
