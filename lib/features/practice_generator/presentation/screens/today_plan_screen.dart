import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routing/app_route.dart';
import '../../../../core/design_system/public.dart';
import '../../../../l10n/app_localizations.dart';
import '../../application/controller/today_plan_controller.dart';
import '../../application/usecase/propose_today_plan_change.dart';
import '../../domain/model/adaptive_practice_plan.dart';
import '../../domain/model/practice_block.dart';
import '../controller/plan_preview_controller.dart';
import '../providers/practice_generator_providers.dart';
import 'plan_change_review_screen.dart';
import 'plan_preview_screen.dart';

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
        // E17-R06 / ADR 0525 §5.2: the four plan sub-screens open from
        // Today's context, never from the shell root. The menu is
        // scope-free itself — each pushed page resolves its own data from
        // the composition root (`practice_generator_providers.dart`).
        actions: const [_TodayPlanMenu()],
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

// ---------------------------------------------------------------------------
// E17-R06 — entry points to the four plan sub-screens (ADR 0525)
// ---------------------------------------------------------------------------

enum _TodayPlanMenuAction { weeklyPlan, planPreview, changeReview, privacy }

/// The Today AppBar overflow menu. One text-labelled item per sub-screen
/// (never icon-only, A3/A4 of the planner accessibility contract); each
/// item pushes a page that reads the ACTIVE plan and the composition
/// root's use cases through `Consumer` scopes of its own, so this screen
/// keeps building without a `ProviderScope` (its existing scope-free
/// widget tests and the 2.0 text-scale cells stay valid).
class _TodayPlanMenu extends StatelessWidget {
  const _TodayPlanMenu();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PopupMenuButton<_TodayPlanMenuAction>(
      key: const Key('today-plan-menu'),
      tooltip: l10n.practiceGeneratorMoreActions,
      onSelected: (action) => _open(context, action),
      itemBuilder: (context) => <PopupMenuEntry<_TodayPlanMenuAction>>[
        PopupMenuItem<_TodayPlanMenuAction>(
          key: const Key('today-plan-open-weekly'),
          value: _TodayPlanMenuAction.weeklyPlan,
          child: Text(l10n.practiceGeneratorOpenWeeklyPlan),
        ),
        PopupMenuItem<_TodayPlanMenuAction>(
          key: const Key('today-plan-open-preview'),
          value: _TodayPlanMenuAction.planPreview,
          child: Text(l10n.practiceGeneratorOpenPlanPreview),
        ),
        PopupMenuItem<_TodayPlanMenuAction>(
          key: const Key('today-plan-open-change-review'),
          value: _TodayPlanMenuAction.changeReview,
          child: Text(l10n.practiceGeneratorOpenChangeReview),
        ),
        PopupMenuItem<_TodayPlanMenuAction>(
          key: const Key('today-plan-open-privacy'),
          value: _TodayPlanMenuAction.privacy,
          child: Text(l10n.practiceGeneratorOpenPrivacy),
        ),
      ],
    );
  }

  void _open(BuildContext context, _TodayPlanMenuAction action) {
    // A heti terv és az adatvédelem a ROUTEREN át nyílik: mindkettőnek van
    // regisztrált címe, amit a router a saját providereiből épít fel, és egy
    // `Navigator`-os megkerülés mély-linkelhetetlenné tenné őket (WP-D).
    // Az előnézet és a változás-áttekintés marad helyben épített lap: azok
    // `extra`-t kérnek (tervet, illetve javaslatot), és `extra` nélkül a
    // router őre visszadobná őket ide — vagyis halott vezérlő lenne.
    switch (action) {
      case _TodayPlanMenuAction.weeklyPlan:
        context.push(AppRoutes.practiceGeneratorWeekly);
      case _TodayPlanMenuAction.privacy:
        context.push(AppRoutes.practiceGeneratorPrivacy);
      case _TodayPlanMenuAction.planPreview:
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const _PlanPreviewRoute()),
        );
      case _TodayPlanMenuAction.changeReview:
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const _PlanChangeReviewRoute(),
          ),
        );
    }
  }
}

/// A titled page carrying one message (an explicit "nothing here yet" or
/// read-failure state) or a progress indicator while a read is pending —
/// the same shape as `WeeklyPlanScreen`'s no-plan branch.
class _MessageScaffold extends StatelessWidget {
  const _MessageScaffold({
    required this.title,
    this.message,
    this.busy = false,
    super.key,
  });

  final String title;
  final String? message;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(SsSpacing.space6),
          child: busy
              ? const CircularProgressIndicator()
              : Text(
                  message ?? '',
                  textAlign: TextAlign.center,
                  style: typography.bodyMedium.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
        ),
      ),
    );
  }
}

/// Resolves the ACTIVE plan for a pushed sub-screen. A read failure is an
/// explicit error page, never reclassified as "no plan yet"
/// (`activePracticePlanProvider`'s M4 contract).
class _ActivePlanRoute extends ConsumerWidget {
  const _ActivePlanRoute({required this.title, required this.builder});

  final String Function(AppLocalizations l10n) title;
  final Widget Function(
    BuildContext context,
    WidgetRef ref,
    AdaptivePracticePlan? plan,
  )
  builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return switch (ref.watch(activePracticePlanProvider)) {
      AsyncData(:final value) => builder(context, ref, value),
      AsyncError() => _MessageScaffold(
        key: const Key('today-plan-route-error'),
        title: title(l10n),
        message: l10n.practiceGeneratorPlanLoadFailed,
      ),
      _ => _MessageScaffold(
        key: const Key('today-plan-route-loading'),
        title: title(l10n),
        busy: true,
      ),
    };
  }
}

class _PlanPreviewRoute extends StatelessWidget {
  const _PlanPreviewRoute();

  @override
  Widget build(BuildContext context) => _ActivePlanRoute(
    title: (l10n) => l10n.planPreviewTitle,
    builder: (context, ref, plan) {
      if (plan == null) {
        final l10n = AppLocalizations.of(context);
        return _MessageScaffold(
          key: const Key('today-plan-preview-no-plan'),
          title: l10n.planPreviewTitle,
          message: l10n.practiceGeneratorNoActivePlanForAction,
        );
      }
      return _PlanPreviewHost(plan: plan);
    },
  );
}

/// Owns ONE [PlanPreviewController] for the pushed preview: built once
/// from the composition root's factory (the real `LocalPracticePlanRepository`
/// activation, ADR 0482 / D4) and disposed with the page — never rebuilt
/// on every frame.
class _PlanPreviewHost extends ConsumerStatefulWidget {
  const _PlanPreviewHost({required this.plan});

  final AdaptivePracticePlan plan;

  @override
  ConsumerState<_PlanPreviewHost> createState() => _PlanPreviewHostState();
}

class _PlanPreviewHostState extends ConsumerState<_PlanPreviewHost> {
  late final PlanPreviewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(planPreviewControllerFactoryProvider)(
      initialPlan: widget.plan,
      validationContext: ref.read(planValidationContextForPlanProvider)(
        widget.plan,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      PlanPreviewScreen(controller: _controller);
}

class _PlanChangeReviewRoute extends ConsumerWidget {
  const _PlanChangeReviewRoute();

  Future<void> _accept(
    BuildContext context,
    WidgetRef ref,
    TodayPlanChangeProposal reviewed,
  ) async {
    final navigator = Navigator.of(context);
    final revision = ref.read(proposeTodayPlanChangeProvider).accept(reviewed);
    if (revision != null) {
      await ref
          .read(localPracticePlanRepositoryProvider)
          .activate(revision.snapshot);
      if (!context.mounted) return;
      ref.invalidate(activePracticePlanProvider);
    }
    navigator.pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return switch (ref.watch(todayPlanChangeProposalProvider)) {
      AsyncData(:final value) =>
        value == null
            ? _MessageScaffold(
                key: const Key('today-plan-change-review-empty'),
                title: l10n.planChangeReviewTitle,
                message: l10n.practiceGeneratorNoChangesToReview,
              )
            : PlanChangeReviewScreen(
                proposal: value.proposal,
                onAccepted: () => _accept(context, ref, value),
                onRejected: () => Navigator.of(context).pop(),
              ),
      AsyncError() => _MessageScaffold(
        key: const Key('today-plan-route-error'),
        title: l10n.planChangeReviewTitle,
        message: l10n.practiceGeneratorPlanLoadFailed,
      ),
      _ => _MessageScaffold(
        key: const Key('today-plan-route-loading'),
        title: l10n.planChangeReviewTitle,
        busy: true,
      ),
    };
  }
}
