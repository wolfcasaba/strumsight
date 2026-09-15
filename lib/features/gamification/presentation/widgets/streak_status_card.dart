import 'package:flutter/material.dart';
import 'package:strumsight/core/design_system/public.dart';
import 'package:strumsight/features/gamification/application/streak_service.dart';
import 'package:strumsight/l10n/app_localizations.dart';

/// Displays the caller-supplied streak evaluation without deriving policy.
class StreakStatusCard extends StatelessWidget {
  const StreakStatusCard({
    super.key,
    required this.reason,
    this.reduceMotion = false,
  });

  final StreakEvaluationReason reason;

  /// Caller-fed reduced-motion preference (e.g.
  /// `GamificationPreferences.reduceMotion`). ORed with
  /// `MediaQuery.disableAnimationsOf` — either source collapses the
  /// transition duration to zero without dropping any content (brief
  /// §5.6 / §6 A8).
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final content = _contentFor(l10n, reason);
    final color = Theme.of(context).colorScheme.primary;
    final duration = (MediaQuery.disableAnimationsOf(context) || reduceMotion)
        ? Duration.zero
        : const Duration(milliseconds: 200);

    return Semantics(
      key: const Key('streak-status-card'),
      label: l10n.streakV2StatusSemantics(content.title, content.body),
      child: ExcludeSemantics(
        child: AnimatedContainer(
          key: const Key('streak-status-transition'),
          duration: duration,
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            border: Border.all(color: color.withValues(alpha: 0.30)),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Ch18 spec §11: the two "your rhythm is lit" reasons show
              // the flame and ignite it once on entry — today's credit made
              // visible; every other reason keeps its own icon. The
              // caller-fed reduceMotion reaches the flame via SsMotionScope.
              if (content.flame)
                SsMotionScope(
                  appOverride: reduceMotion ? true : null,
                  child: SsFlame(
                    lit: true,
                    color: color,
                    size: SsFlameSize.medium,
                    igniteOnMount: true,
                  ),
                )
              else
                Icon(content.icon, color: color),
              const SizedBox(height: 12),
              Text(
                content.title,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              Text(content.body, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ),
    );
  }
}

({String title, String body, IconData icon, bool flame}) _contentFor(
  AppLocalizations l10n,
  StreakEvaluationReason reason,
) => switch (reason) {
  StreakEvaluationReason.qualified => (
    title: l10n.streakV2QualifiedTitle,
    body: l10n.streakV2QualifiedBody,
    icon: Icons.local_fire_department_outlined,
    flame: true,
  ),
  StreakEvaluationReason.recoveryQualified => (
    title: l10n.streakV2RecoveryQualifiedTitle,
    body: l10n.streakV2RecoveryQualifiedBody,
    icon: Icons.self_improvement_outlined,
    flame: false,
  ),
  StreakEvaluationReason.insufficientActivity => (
    title: l10n.streakV2InsufficientTitle,
    body: l10n.streakV2InsufficientBody,
    icon: Icons.spa_outlined,
    flame: false,
  ),
  StreakEvaluationReason.plannedRest => (
    title: l10n.streakV2PlannedRestTitle,
    body: l10n.streakV2PlannedRestBody,
    icon: Icons.bedtime_outlined,
    flame: false,
  ),
  StreakEvaluationReason.grace => (
    title: l10n.streakV2GraceTitle,
    body: l10n.streakV2GraceBody,
    icon: Icons.air_outlined,
    flame: false,
  ),
  StreakEvaluationReason.freezeCovered => (
    title: l10n.streakV2FreezeCoveredTitle,
    body: l10n.streakV2FreezeCoveredBody,
    icon: Icons.ac_unit,
    flame: false,
  ),
  StreakEvaluationReason.broken => (
    title: l10n.streakV2BrokenTitle,
    body: l10n.streakV2BrokenBody,
    icon: Icons.favorite_outline,
    flame: false,
  ),
  StreakEvaluationReason.alreadyQualified => (
    title: l10n.streakV2AlreadyQualifiedTitle,
    body: l10n.streakV2AlreadyQualifiedBody,
    icon: Icons.check_circle_outline,
    flame: true,
  ),
  StreakEvaluationReason.clockAnomaly => (
    title: l10n.streakV2ClockAnomalyTitle,
    body: l10n.streakV2ClockAnomalyBody,
    icon: Icons.schedule_outlined,
    flame: false,
  ),
};
