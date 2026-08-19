import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice_generator/public.dart';

import '../../../fixtures/practice_generator/assist/planner_assist_fixtures.dart';

void main() {
  group('PlannerAssistGateway', () {
    test(
      'A1: a valid model response remains a non-executable proposal',
      () async {
        final gateway = FakePlannerAssistGateway(
          events: <PlannerAssistEvent>[
            PlannerAssistSuggestion(
              (PlannerAssistSchema.validate(
                        buildPlannerAssistRequest(),
                        validPlannerAssistResponse(),
                      )
                      as PlannerAssistAccepted)
                  .proposal,
            ),
          ],
        );

        final event = await gateway
            .suggest(
              buildPlannerAssistRequest(),
              const PlannerAssistNeverCancelled(),
            )
            .single;

        expect(event, isA<PlannerAssistSuggestion>());
        expect(
          (event as PlannerAssistSuggestion).proposal.lifecycle,
          PlannerAssistProposalLifecycle.awaitingConfirmation,
        );
      },
    );

    test(
      'A4 + A5: timeout keeps the caller-owned draft untouched and falls back',
      () async {
        final pendingResponse = Completer<Object?>();
        final gateway = RemotePlannerAssistGateway(
          transport: _Transport((_) => pendingResponse.future),
          requestTimeout: Duration.zero,
        );
        final draft = buildPlannerAssistRequest();

        final event = await gateway
            .suggest(draft, const PlannerAssistNeverCancelled())
            .single;

        expect(
          event,
          const PlannerAssistFallback(PlannerAssistFallbackReason.timeout),
        );
        expect(draft, buildPlannerAssistRequest());
      },
    );

    test('A4: rate limiting falls back deterministically', () async {
      final gateway = RemotePlannerAssistGateway(
        transport: _Transport(
          (_) => Future<Object?>.error(const PlannerAssistRateLimitException()),
        ),
      );

      final event = await gateway
          .suggest(
            buildPlannerAssistRequest(),
            const PlannerAssistNeverCancelled(),
          )
          .single;

      expect(
        event,
        const PlannerAssistFallback(PlannerAssistFallbackReason.rateLimited),
      );
    });

    test(
      'A4: network failure and cancellation never emit a model proposal',
      () async {
        final networkGateway = RemotePlannerAssistGateway(
          transport: _Transport(
            (_) => Future<Object?>.error(const PlannerAssistNetworkException()),
          ),
        );
        final cancelledGateway = RemotePlannerAssistGateway(
          transport: _Transport((_) => throw StateError('must not be called')),
        );

        final networkEvent = await networkGateway
            .suggest(
              buildPlannerAssistRequest(),
              const PlannerAssistNeverCancelled(),
            )
            .single;
        final cancelledEvent = await cancelledGateway
            .suggest(buildPlannerAssistRequest(), const _Cancelled())
            .single;

        expect(
          networkEvent,
          const PlannerAssistFallback(
            PlannerAssistFallbackReason.networkFailure,
          ),
        );
        expect(
          cancelledEvent,
          const PlannerAssistFallback(PlannerAssistFallbackReason.cancelled),
        );
      },
    );

    test(
      'A7: disabled assistance returns the offline fallback without calling transport',
      () async {
        final gateway = FakePlannerAssistGateway.disabled();

        final event = await gateway
            .suggest(
              buildPlannerAssistRequest(),
              const PlannerAssistNeverCancelled(),
            )
            .single;

        expect(
          event,
          const PlannerAssistFallback(PlannerAssistFallbackReason.disabled),
        );
      },
    );

    test(
      'A8: maps a typed Tutor outline to a validated, allowlisted request',
      () {
        final adapter = TutorPlanProposalAdapter(
          catalogReader: _CatalogReader(buildPlannerAssistCatalog()),
        );
        final request = adapter.toRequest(
          requestId: 'outline-1',
          locale: 'en',
          outline: TutorPlanOutline(
            goalIds: <GoalId>[GoalId(plannerAssistGoal)],
            skillIds: const <String>[plannerAssistSkill],
            learnerNote: 'Keep this practical.',
          ),
        );

        final result = PlannerAssistSchema.validate(
          request,
          validPlannerAssistResponse(),
        );

        expect(
          request.allowlist.candidateIds,
          contains(plannerAssistCandidate),
        );
        expect(result, isA<PlannerAssistAccepted>());
      },
    );
  });
}

final class _Transport implements PlannerAssistTransport {
  const _Transport(this._respond);

  final Future<Object?> Function(PlannerAssistPrompt) _respond;

  @override
  Future<Object?> request(PlannerAssistPrompt prompt) => _respond(prompt);
}

final class _Cancelled implements PlannerAssistCancellationToken {
  const _Cancelled();

  @override
  bool get isCancelled => true;
}

final class _CatalogReader implements PracticeCatalogReader {
  const _CatalogReader(this._catalog);

  final PracticeCatalogSnapshot _catalog;

  @override
  PracticeCatalogSnapshot read() => _catalog;
}
