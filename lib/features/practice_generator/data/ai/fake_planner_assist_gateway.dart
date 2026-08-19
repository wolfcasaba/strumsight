/// Deterministic offline/test implementation of [PlannerAssistGateway].
library;

import '../../application/port/planner_assist_gateway.dart';

final class FakePlannerAssistGateway implements PlannerAssistGateway {
  FakePlannerAssistGateway({Iterable<PlannerAssistEvent> events = const []})
    : _events = List<PlannerAssistEvent>.unmodifiable(events),
      _enabled = true;

  FakePlannerAssistGateway.disabled()
    : _events = const <PlannerAssistEvent>[],
      _enabled = false;

  final List<PlannerAssistEvent> _events;
  final bool _enabled;

  @override
  Stream<PlannerAssistEvent> suggest(
    PlannerAssistRequest request,
    PlannerAssistCancellationToken cancellation,
  ) {
    if (cancellation.isCancelled) {
      return Stream<PlannerAssistEvent>.value(
        const PlannerAssistFallback(PlannerAssistFallbackReason.cancelled),
      );
    }
    if (!_enabled) {
      return Stream<PlannerAssistEvent>.value(
        const PlannerAssistFallback(PlannerAssistFallbackReason.disabled),
      );
    }
    if (_events.isEmpty) {
      return Stream<PlannerAssistEvent>.value(
        const PlannerAssistFallback(PlannerAssistFallbackReason.noSuggestion),
      );
    }
    return Stream<PlannerAssistEvent>.fromIterable(_events);
  }
}
