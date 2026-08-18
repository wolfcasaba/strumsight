import 'package:flutter/material.dart';

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
      appBar: AppBar(title: Text(l10n.todayPlanTitle)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: switch (state.mode) {
            TodayPlanMode.noActivePlan => _EmptyState(l10n: l10n),
            TodayPlanMode.restDay => _MessageState(
              stateKey: const Key('today-plan-rest-day'),
              title: l10n.todayPlanRestTitle,
              body: l10n.todayPlanRestBody,
            ),
            TodayPlanMode.unavailableDay => _MessageState(
              stateKey: const Key('today-plan-unavailable-day'),
              title: l10n.todayPlanUnavailableTitle,
              body: l10n.todayPlanUnavailableBody,
            ),
            TodayPlanMode.completedDay => _MessageState(
              stateKey: const Key('today-plan-completed-day'),
              title: l10n.todayPlanCompletedTitle,
              body: l10n.todayPlanCompletedBody,
            ),
            TodayPlanMode.notScheduled => _MessageState(
              stateKey: const Key('today-plan-not-scheduled'),
              title: l10n.todayPlanNotScheduledTitle,
              body: l10n.todayPlanNotScheduledBody,
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
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) => Column(
    key: const Key('today-plan-empty'),
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Text(
        l10n.todayPlanEmptyTitle,
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 8),
      Text(l10n.todayPlanEmptyBody),
    ],
  );
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required Key stateKey,
    required this.title,
    required this.body,
  }) : super(key: stateKey);

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      Text(body),
    ],
  );
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
    final next = state.nextBlock;
    return Column(
      key: const Key('today-plan-scheduled'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.todayPlanRemaining(_formatDuration(state.remainingTime))),
        const SizedBox(height: 16),
        Text(
          l10n.todayPlanNextBlock,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(next == null ? l10n.todayPlanNothingRemaining : next.kind.code),
        const Spacer(),
        FilledButton(
          key: const Key('today-plan-start'),
          onPressed: next == null || onStart == null
              ? null
              : () => onStart!(next),
          child: Text(l10n.todayPlanStart),
        ),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          children: [
            TextButton(
              key: const Key('today-plan-swap'),
              onPressed: next == null || onSwap == null
                  ? null
                  : () => onSwap!(next),
              child: Text(l10n.todayPlanSwap),
            ),
            TextButton(
              key: const Key('today-plan-skip'),
              onPressed: next == null || onSkip == null
                  ? null
                  : () => onSkip!(next),
              child: Text(l10n.todayPlanSkip),
            ),
            TextButton(
              key: const Key('today-plan-shorten'),
              onPressed: onShorten,
              child: Text(l10n.todayPlanShorten),
            ),
            TextButton(
              key: const Key('today-plan-pause'),
              onPressed: onPause,
              child: Text(l10n.todayPlanPause),
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
