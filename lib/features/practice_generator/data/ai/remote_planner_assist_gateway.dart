/// Transport-backed, failure-contained PlannerAssist implementation.
library;

import 'dart:async';

import '../../application/port/planner_assist_gateway.dart';
import 'planner_assist_schema.dart';

/// Small transport seam; an integration layer may implement it with HTTP.
abstract interface class PlannerAssistTransport {
  Future<Object?> request(PlannerAssistPrompt prompt);
}

final class PlannerAssistRateLimitException implements Exception {
  const PlannerAssistRateLimitException();
}

final class PlannerAssistNetworkException implements Exception {
  const PlannerAssistNetworkException();
}

/// Converts every optional-cloud failure into a deterministic fallback event.
final class RemotePlannerAssistGateway implements PlannerAssistGateway {
  RemotePlannerAssistGateway({
    required this.transport,
    this.requestTimeout = const Duration(seconds: 10),
  }) {
    if (requestTimeout.isNegative) {
      throw ArgumentError.value(requestTimeout, 'requestTimeout');
    }
  }

  final PlannerAssistTransport transport;
  final Duration requestTimeout;

  @override
  Stream<PlannerAssistEvent> suggest(
    PlannerAssistRequest request,
    PlannerAssistCancellationToken cancellation,
  ) async* {
    if (cancellation.isCancelled) {
      yield const PlannerAssistFallback(PlannerAssistFallbackReason.cancelled);
      return;
    }
    final Object? raw;
    try {
      raw = await transport.request(request.toPrompt()).timeout(requestTimeout);
    } on TimeoutException {
      yield const PlannerAssistFallback(PlannerAssistFallbackReason.timeout);
      return;
    } on PlannerAssistRateLimitException {
      yield const PlannerAssistFallback(
        PlannerAssistFallbackReason.rateLimited,
      );
      return;
    } on PlannerAssistNetworkException {
      yield const PlannerAssistFallback(
        PlannerAssistFallbackReason.networkFailure,
      );
      return;
    } catch (_) {
      yield const PlannerAssistFallback(
        PlannerAssistFallbackReason.networkFailure,
      );
      return;
    }
    if (cancellation.isCancelled) {
      yield const PlannerAssistFallback(PlannerAssistFallbackReason.cancelled);
      return;
    }
    switch (PlannerAssistSchema.validate(request, raw)) {
      case PlannerAssistAccepted(:final proposal):
        yield PlannerAssistSuggestion(proposal);
      case PlannerAssistRejected():
        yield const PlannerAssistFallback(
          PlannerAssistFallbackReason.schemaRejected,
        );
    }
  }
}
