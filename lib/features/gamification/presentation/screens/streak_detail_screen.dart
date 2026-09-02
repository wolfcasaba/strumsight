import 'package:flutter/material.dart';
import 'package:strumsight/core/design_system/public.dart';
import 'package:strumsight/features/gamification/application/streak_service.dart';
import 'package:strumsight/features/gamification/domain/streak/streak_state.dart';
import 'package:strumsight/features/gamification/presentation/widgets/gamification_theme_scope.dart';
import 'package:strumsight/features/gamification/presentation/widgets/streak_status_card.dart';
import 'package:strumsight/features/gamification/presentation/widgets/weekly_consistency_card.dart';
import 'package:strumsight/l10n/app_localizations.dart';

/// Caller-fed Streak V2 presentation with no policy, route, or storage owner.
class StreakDetailScreen extends StatelessWidget {
  StreakDetailScreen({
    super.key,
    required this.state,
    required this.reason,
    required this.weeklyConsistencyDays,
    required this.onRecoveryPressed,
    this.reduceMotion = false,
  }) {
    if (weeklyConsistencyDays < 0 || weeklyConsistencyDays > 7) {
      throw ArgumentError.value(
        weeklyConsistencyDays,
        'weeklyConsistencyDays',
        'must be between 0 and 7',
      );
    }
  }

  final StreakState state;
  final StreakEvaluationReason reason;
  final int weeklyConsistencyDays;
  final VoidCallback onRecoveryPressed;

  /// Caller-fed reduced-motion preference (e.g. `GamificationPreferences.reduceMotion`).
  /// ORed with `MediaQuery.disableAnimationsOf` inside [StreakStatusCard] —
  /// either source collapses the transition duration to zero without
  /// dropping any content (brief §5.6 / §6 A8).
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return GamificationThemeScope(
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.streakV2Title)),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              SsSpacing.space5,
              SsSpacing.space3,
              SsSpacing.space5,
              SsSpacing.space6,
            ),
            children: [
              StreakStatusCard(reason: reason, reduceMotion: reduceMotion),
              const SizedBox(height: SsSpacing.space4),
              LayoutBuilder(
                builder: (context, constraints) {
                  final cardWidth =
                      (constraints.maxWidth - SsSpacing.space3) / 2;
                  return Wrap(
                    spacing: SsSpacing.space3,
                    runSpacing: SsSpacing.space3,
                    children: [
                      SizedBox(
                        width: cardWidth,
                        child: _StreakMetricCard(
                          icon: Icons.local_fire_department_outlined,
                          value: state.current,
                          label: l10n.streakV2CurrentLabel,
                          semantics: l10n.streakV2CurrentSemantics(
                            state.current,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: cardWidth,
                        child: _StreakMetricCard(
                          icon: Icons.emoji_events_outlined,
                          value: state.longest,
                          label: l10n.streakV2LongestLabel,
                          semantics: l10n.streakV2LongestSemantics(
                            state.longest,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: cardWidth,
                        child: _StreakMetricCard(
                          icon: Icons.calendar_today_outlined,
                          value: state.totalQualifiedDays,
                          label: l10n.streakV2TotalLabel,
                          semantics: l10n.streakV2TotalSemantics(
                            state.totalQualifiedDays,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: cardWidth,
                        child: _StreakMetricCard(
                          icon: Icons.ac_unit,
                          value: state.freezes,
                          label: l10n.streakV2FreezesLabel,
                          semantics: l10n.streakV2FreezesSemantics(
                            state.freezes,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: SsSpacing.space4),
              WeeklyConsistencyCard(days: weeklyConsistencyDays),
              if (reason == StreakEvaluationReason.broken) ...[
                const SizedBox(height: SsSpacing.space4),
                SsButton(
                  key: const Key('streak-recovery-cta'),
                  label: l10n.streakV2RecoveryCta,
                  icon: Icons.play_arrow_outlined,
                  onPressed: onRecoveryPressed,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StreakMetricCard extends StatelessWidget {
  const _StreakMetricCard({
    required this.icon,
    required this.value,
    required this.label,
    required this.semantics,
  });

  final IconData icon;
  final int value;
  final String label;
  final String semantics;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: semantics,
    child: ExcludeSemantics(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon),
              const SizedBox(height: 12),
              Text(
                value.toString(),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Text(label, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ),
    ),
  );
}
