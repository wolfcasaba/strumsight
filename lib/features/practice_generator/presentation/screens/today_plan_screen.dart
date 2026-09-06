import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routing/app_route.dart';
import '../../../../core/design_system/public.dart';
import '../../../../l10n/app_localizations.dart';
import '../../application/controller/today_plan_controller.dart';
import '../../domain/model/adaptive_practice_plan.dart';
import '../../domain/model/practice_block.dart';

/// The local, offline Today projection of the learner's active plan.
class TodayPlanScreen extends StatelessWidget {
  const TodayPlanScreen({
    required this.controller,
    this.plan,
    this.launchRequest,
    this.isDeepLinkLaunch = false,
    this.isTodayRouteEnabled = false,
    this.onStart,
    this.onSwap,
    this.onSkip,
    this.onShorten,
    this.onPause,
    super.key,
  });

  final TodayPlanController controller;
  final AdaptivePracticePlan? plan;
  final TodayPlanRouteRequest? launchRequest;

  /// Preserves an attempted deep-link launch when [launchRequest] was rejected.
  ///
  /// Routing must set this when it calls [TodayPlanRouteRequest.tryParse], so
  /// a malformed payload cannot be mistaken for an in-app launch.
  final bool isDeepLinkLaunch;
  final bool isTodayRouteEnabled;
  final ValueChanged<PracticeBlock>? onStart;
  final ValueChanged<PracticeBlock>? onSwap;
  final ValueChanged<PracticeBlock>? onSkip;
  final VoidCallback? onShorten;
  final VoidCallback? onPause;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDeepLinkContext = isDeepLinkLaunch || launchRequest != null;
    final planForState = isDeepLinkContext
        ? launchRequest?.permits(
                    activePlan: plan,
                    isFeatureEnabled: isTodayRouteEnabled,
                  ) ==
                  true
              ? plan
              : null
        : plan;
    final state = controller.resolve(planForState);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.todayPlanTitle),
        // A tervező két MELLÉK-képernyője (`/practice/generator/weekly`,
        // `/practice/generator/privacy`) be volt kötve, de a szállított
        // felületről semmi nem vezetett hozzájuk. Mindkettőt a router a
        // saját providereiből építi fel — `extra` nélkül megnyithatók,
        // ezért ez a képernyő el TUDJA érni őket. Az előnézet és a
        // változás-áttekintés NEM kap itt belépési pontot: azok a
        // folyamat lépései, és `extra` nélkül a mai tervre esnének vissza
        // (l. a router redirect-őrét) — egy ilyen gomb visszadobná a
        // felhasználót ugyanide, azaz halott vezérlő lenne.
        actions: <Widget>[
          IconButton(
            key: const Key('today-plan-open-weekly'),
            onPressed: () => context.push(AppRoutes.practiceGeneratorWeekly),
            icon: const Icon(Icons.calendar_month_outlined),
            tooltip: l10n.weeklyPlanTitle,
          ),
          IconButton(
            key: const Key('today-plan-open-privacy'),
            onPressed: () => context.push(AppRoutes.practiceGeneratorPrivacy),
            icon: const Icon(Icons.privacy_tip_outlined),
            tooltip: l10n.practicePrivacyTitle,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(SsSpacing.space5),
          child: _ScrollableIfShort(
            child: switch (state.mode) {
              TodayPlanMode.noActivePlan => _EmptyState(l10n: l10n),
              TodayPlanMode.restDay => _MessageState(
                stateKey: const Key('today-plan-rest-day'),
                title: l10n.todayPlanRestTitle,
                body: l10n.todayPlanRestBody,
                statusLabel: l10n.practicePlanStatusRestLabel,
              ),
              TodayPlanMode.unavailableDay => _MessageState(
                stateKey: const Key('today-plan-unavailable-day'),
                title: l10n.todayPlanUnavailableTitle,
                body: l10n.todayPlanUnavailableBody,
                statusLabel: l10n.practicePlanStatusUnavailableLabel,
              ),
              TodayPlanMode.completedDay => _MessageState(
                stateKey: const Key('today-plan-completed-day'),
                title: l10n.todayPlanCompletedTitle,
                body: l10n.todayPlanCompletedBody,
                statusLabel: l10n.practicePlanStatusCompletedLabel,
              ),
              TodayPlanMode.notScheduled => _MessageState(
                stateKey: const Key('today-plan-not-scheduled'),
                title: l10n.todayPlanNotScheduledTitle,
                body: l10n.todayPlanNotScheduledBody,
                statusLabel: l10n.practicePlanStatusNotScheduledLabel,
              ),
              TodayPlanMode.plannedDay => _PlannedDay(
                state: state,
                onStart: onStart,
                onSwap: onSwap,
                onSkip: onSkip,
                onShorten: onShorten,
                onPause: onPause,
              ),
            },
          ),
        ),
      ),
    );
  }
}

/// Lets [child] scroll instead of overflow when the viewport is too short
/// for it (§0.0.A/R7, L558) — measured need: at `textScaler` 2.0 on a
/// phone-sized (360x640) viewport, the empty/message states' status badge +
/// title + body, and the planned-day state's status + remaining time + next
/// block + action buttons, can together outgrow a short viewport. Mirrors
/// the `_ScrollableIfShort` pattern already established on
/// `setlist_list_screen.dart`/`setlist_detail_screen.dart` (E15-R06).
class _ScrollableIfShort extends StatelessWidget {
  const _ScrollableIfShort({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedHeight) return child;
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: child,
          ),
        );
      },
    );
  }
}

/// A textual status marker — icon + label, never colour alone (A4). Not
/// [SsStatusBadge]: that component's [SsStatusBadgeKind] enumerates
/// offline/sync/confidence states only, none of which describe a practice
/// plan's day status (rest / unavailable / completed / planned / no-active)
/// — inventing a mapping would misrepresent the state (§5.2).
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
    return Semantics(
      label: label,
      container: true,
      child: Row(
        key: const Key('today-plan-status-badge'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: colors.textPrimary,
            semanticLabel: 'status',
          ),
          const SizedBox(width: SsSpacing.space1),
          Flexible(
            child: Text(
              label,
              style: typography.labelLarge.copyWith(color: colors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
    return Column(
      key: const Key('today-plan-empty'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _StatusBadge(
          label: l10n.practicePlanStatusNoActiveLabel,
          icon: Icons.info_outline,
        ),
        const SizedBox(height: SsSpacing.space3),
        Text(
          l10n.todayPlanEmptyTitle,
          style: typography.titleLarge.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: SsSpacing.space2),
        Text(
          l10n.todayPlanEmptyBody,
          style: typography.bodyMedium.copyWith(color: colors.textSecondary),
        ),
      ],
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required Key stateKey,
    required this.title,
    required this.body,
    this.statusLabel,
  }) : super(key: stateKey);

  final String title;
  final String body;

  /// An optional, semantics-labelled status badge. The status is never
  /// communicated by colour alone (A4) — this badge is text + icon so
  /// screen readers and colour-blind users see the same information.
  final String? statusLabel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (statusLabel != null) ...[
          _StatusBadge(label: statusLabel!, icon: Icons.info_outline),
          const SizedBox(height: SsSpacing.space3),
        ],
        Text(
          title,
          style: typography.titleLarge.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: SsSpacing.space2),
        Text(
          body,
          style: typography.bodyMedium.copyWith(color: colors.textSecondary),
        ),
      ],
    );
  }
}

class _PlannedDay extends StatelessWidget {
  const _PlannedDay({
    required this.state,
    required this.onStart,
    required this.onSwap,
    required this.onSkip,
    required this.onShorten,
    required this.onPause,
  });

  final TodayPlanState state;
  final ValueChanged<PracticeBlock>? onStart;
  final ValueChanged<PracticeBlock>? onSwap;
  final ValueChanged<PracticeBlock>? onSkip;
  final VoidCallback? onShorten;
  final VoidCallback? onPause;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
    final next = state.nextBlock;
    return Column(
      key: const Key('today-plan-scheduled'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StatusBadge(
          label: l10n.practicePlanStatusPlannedLabel,
          icon: Icons.event_note,
        ),
        const SizedBox(height: SsSpacing.space3),
        Text(
          l10n.todayPlanRemaining(_formatDuration(state.remainingTime)),
          style: typography.bodyMedium.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: SsSpacing.space4),
        Text(
          l10n.todayPlanNextBlock,
          style: typography.titleMedium.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: SsSpacing.space1),
        Text(
          next == null ? l10n.todayPlanNothingRemaining : next.kind.code,
          style: typography.bodyMedium.copyWith(color: colors.textSecondary),
        ),
        // A fixed gap, not `Spacer()` (§0.0.A/R7 fallout): once the column
        // sits inside `_ScrollableIfShort`'s scrollable branch, the main
        // axis is unbounded and a flex child like `Spacer` throws. The
        // start button no longer pins to the bottom of the viewport, but
        // the same buttons, in the same order, are still all present —
        // §0.0's behavior/order/state invariant, not the exact pixel
        // position, is what's frozen.
        const SizedBox(height: SsSpacing.space6),
        SsButton(
          key: const Key('today-plan-start'),
          onPressed: next == null || onStart == null
              ? null
              : () => onStart!(next),
          label: l10n.todayPlanStart,
        ),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: SsSpacing.space2,
          children: [
            SsButton(
              key: const Key('today-plan-swap'),
              variant: SsButtonVariant.tertiary,
              onPressed: next == null || onSwap == null
                  ? null
                  : () => onSwap!(next),
              label: l10n.todayPlanSwap,
            ),
            SsButton(
              key: const Key('today-plan-skip'),
              variant: SsButtonVariant.tertiary,
              onPressed: next == null || onSkip == null
                  ? null
                  : () => onSkip!(next),
              label: l10n.todayPlanSkip,
            ),
            SsButton(
              key: const Key('today-plan-shorten'),
              variant: SsButtonVariant.tertiary,
              onPressed: onShorten,
              label: l10n.todayPlanShorten,
            ),
            SsButton(
              key: const Key('today-plan-pause'),
              variant: SsButtonVariant.tertiary,
              onPressed: onPause,
              label: l10n.todayPlanPause,
            ),
          ],
        ),
      ],
    );
  }
}

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes;
  if (minutes < 60) return '${minutes}m';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '${hours}h' : '${hours}h${rest}m';
}
