import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/ai_tutor/application/orchestration/action_confirmation_service.dart';
import 'package:strumsight/features/ai_tutor/application/orchestration/fake_action_executors.dart';
import 'package:strumsight/features/ai_tutor/application/orchestration/tutor_action_validator.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_action.dart';

void main() {
  final now = DateTime.utc(2026, 8, 5, 10);

  group('ActionConfirmationService', () {
    test(
      'keeps every supported write or launch pending until confirmation',
      () {
        final executor = FakeTutorActionExecutor();
        final service = ActionConfirmationService(executor: executor);
        final context = _context(now: now);
        final actions = <TutorActionProposal>[
          TutorProfileUpdateAction(
            metadata: _metadata(
              capability: TutorActionCapability.updateProfile,
              clientActionId: 'profile',
            ),
            changes: const <String, Object?>{'preferredTempo': 120},
          ),
          TutorPlanSaveAction(
            metadata: _metadata(
              capability: TutorActionCapability.savePlan,
              clientActionId: 'plan',
            ),
            planId: 'plan-1',
            title: 'Rhythm',
          ),
          TutorSessionLaunchAction(
            metadata: _metadata(
              capability: TutorActionCapability.launchPracticeSession,
              clientActionId: 'launch',
            ),
            launchCapability: TutorSessionLaunchCapability.practiceSession,
          ),
        ];

        final proposals = <ActionConfirmation>[
          for (final action in actions)
            service.propose(action, context: context),
        ];

        expect(
          proposals.map((proposal) => proposal.state),
          everyElement(ActionConfirmationState.pendingConfirmation),
        );
        expect(executor.actions, isEmpty);
      },
    );

    test('provides the profile update preview before confirmation', () {
      final executor = FakeTutorActionExecutor();
      final service = ActionConfirmationService(executor: executor);
      final proposal = service.propose(
        TutorProfileUpdateAction(
          metadata: _metadata(capability: TutorActionCapability.updateProfile),
          changes: const <String, Object?>{'preferredTempo': 120},
        ),
        context: _context(now: now),
      );

      expect(proposal.state, ActionConfirmationState.pendingConfirmation);
      expect(proposal.preview?.kind, TutorActionPreviewKind.profileUpdate);
      expect(proposal.preview?.fields, <String, Object?>{
        'preferredTempo': 120,
      });
      expect(executor.actions, isEmpty);
    });

    test('rejects an unknown action proposal', () {
      final service = ActionConfirmationService(
        executor: FakeTutorActionExecutor(),
      );

      final proposal = service.propose(
        TutorUnknownActionProposal(
          metadata: _metadata(capability: TutorActionCapability.updateProfile),
          actionType: 'eraseEverything',
        ),
        context: _context(now: now),
      );

      expect(proposal.state, ActionConfirmationState.blocked);
      expect(
        proposal.validationIssues,
        contains(TutorActionValidationIssue.unknownAction),
      );
    });

    test('blocks an action expired before confirmation time', () async {
      final service = ActionConfirmationService(
        executor: FakeTutorActionExecutor(),
      );
      final initialContext = _context(
        now: now.subtract(const Duration(microseconds: 2)),
      );

      final proposed = service.propose(
        _profileAction(
          expiresAt: now.subtract(const Duration(microseconds: 1)),
        ),
        context: initialContext,
      );
      final confirmation = await service.confirm(
        proposed,
        context: _context(now: now),
      );

      expect(proposed.state, ActionConfirmationState.pendingConfirmation);
      expect(confirmation.state, ActionConfirmationState.blocked);
      expect(
        confirmation.validationIssues,
        contains(TutorActionValidationIssue.expired),
      );
    });

    test('blocks an action expiring exactly at confirmation time', () async {
      final service = ActionConfirmationService(
        executor: FakeTutorActionExecutor(),
      );
      final initialContext = _context(
        now: now.subtract(const Duration(microseconds: 1)),
      );

      final proposed = service.propose(
        _profileAction(expiresAt: now),
        context: initialContext,
      );
      final confirmation = await service.confirm(
        proposed,
        context: _context(now: now),
      );

      expect(proposed.state, ActionConfirmationState.pendingConfirmation);
      expect(confirmation.state, ActionConfirmationState.blocked);
      expect(
        confirmation.validationIssues,
        contains(TutorActionValidationIssue.expired),
      );
    });

    test('confirms an action when expiry is after confirmation time', () async {
      final executor = FakeTutorActionExecutor();
      final service = ActionConfirmationService(executor: executor);

      final proposed = service.propose(
        _profileAction(expiresAt: now.add(const Duration(microseconds: 1))),
        context: _context(now: now),
      );
      final confirmation = await service.confirm(
        proposed,
        context: _context(now: now),
      );

      expect(proposed.state, ActionConfirmationState.pendingConfirmation);
      expect(confirmation.state, ActionConfirmationState.confirmed);
      expect(executor.actions, hasLength(1));
    });

    test(
      'blocks a song action whose revision changed after proposal',
      () async {
        final executor = FakeTutorActionExecutor();
        final service = ActionConfirmationService(executor: executor);
        final action = TutorSessionLaunchAction(
          metadata: _metadata(
            capability: TutorActionCapability.launchSongRange,
            validity: const TutorActionValidity(
              songId: 'song-1',
              songRevision: TutorActionRevisionToken('revision-1'),
            ),
          ),
          launchCapability: TutorSessionLaunchCapability.songRange,
        );

        final proposed = service.propose(
          action,
          context: _context(
            now: now,
            songRevisions: const <String, TutorActionRevisionToken>{
              'song-1': TutorActionRevisionToken('revision-1'),
            },
          ),
        );
        final confirmation = await service.confirm(
          proposed,
          context: _context(
            now: now,
            songRevisions: const <String, TutorActionRevisionToken>{
              'song-1': TutorActionRevisionToken('revision-2'),
            },
          ),
        );

        expect(proposed.state, ActionConfirmationState.pendingConfirmation);
        expect(confirmation.state, ActionConfirmationState.blocked);
        expect(
          confirmation.validationIssues,
          contains(TutorActionValidationIssue.songRevisionChanged),
        );
        expect(executor.actions, isEmpty);
      },
    );

    test('blocks a session action whose source session was deleted', () async {
      final executor = FakeTutorActionExecutor();
      final service = ActionConfirmationService(executor: executor);
      final action = TutorSessionLaunchAction(
        metadata: _metadata(
          capability: TutorActionCapability.launchPracticeSession,
          validity: const TutorActionValidity(sourceSessionId: 'session-1'),
        ),
        launchCapability: TutorSessionLaunchCapability.practiceSession,
      );

      final proposed = service.propose(
        action,
        context: _context(
          now: now,
          activeSessionIds: const <String>{'session-1'},
        ),
      );
      final confirmation = await service.confirm(
        proposed,
        context: _context(now: now),
      );

      expect(proposed.state, ActionConfirmationState.pendingConfirmation);
      expect(confirmation.state, ActionConfirmationState.blocked);
      expect(
        confirmation.validationIssues,
        contains(TutorActionValidationIssue.sourceSessionUnavailable),
      );
      expect(executor.actions, isEmpty);
    });

    test('blocks an action when its required capability is lost', () async {
      final executor = FakeTutorActionExecutor();
      final service = ActionConfirmationService(executor: executor);

      final proposed = service.propose(
        _profileAction(),
        context: _context(now: now),
      );
      final confirmation = await service.confirm(
        proposed,
        context: _context(
          now: now,
          capabilities: const <TutorActionCapability>{},
        ),
      );

      expect(proposed.state, ActionConfirmationState.pendingConfirmation);
      expect(confirmation.state, ActionConfirmationState.blocked);
      expect(
        confirmation.validationIssues,
        contains(TutorActionValidationIssue.capabilityUnavailable),
      );
      expect(executor.actions, isEmpty);
    });

    test(
      'executes concurrent double confirms only once by client action id',
      () async {
        final executor = FakeTutorActionExecutor();
        final service = ActionConfirmationService(executor: executor);
        final context = _context(now: now);
        final proposed = service.propose(_profileAction(), context: context);

        final confirmations = await Future.wait(<Future<ActionConfirmation>>[
          service.confirm(proposed, context: context),
          service.confirm(proposed, context: context),
        ]);

        expect(
          confirmations.map((confirmation) => confirmation.state),
          everyElement(ActionConfirmationState.confirmed),
        );
        expect(executor.actions, hasLength(1));
        expect(executor.actions.single.metadata.clientActionId, 'action-1');
      },
    );

    test('keeps a rejected proposal clear of execution', () async {
      final executor = FakeTutorActionExecutor();
      final service = ActionConfirmationService(executor: executor);
      final context = _context(now: now);
      final proposed = service.propose(_profileAction(), context: context);

      final rejected = service.reject(proposed);
      final afterConfirm = await service.confirm(rejected, context: context);

      expect(rejected.state, ActionConfirmationState.rejected);
      expect(afterConfirm.state, ActionConfirmationState.rejected);
      expect(executor.actions, isEmpty);
    });

    test('blocks an arbitrary raw route before it reaches an executor', () {
      final executor = FakeTutorActionExecutor();
      final service = ActionConfirmationService(executor: executor);

      final proposal = service.propose(
        TutorRawRouteActionProposal(
          metadata: _metadata(
            capability: TutorActionCapability.launchPracticeSession,
          ),
          route: '/settings',
        ),
        context: _context(now: now),
      );

      expect(proposal.state, ActionConfirmationState.blocked);
      expect(
        proposal.validationIssues,
        contains(TutorActionValidationIssue.rawRouteForbidden),
      );
      expect(executor.actions, isEmpty);
    });
  });
}

TutorActionValidationContext _context({
  required DateTime now,
  Set<TutorActionCapability> capabilities = const <TutorActionCapability>{
    TutorActionCapability.updateProfile,
    TutorActionCapability.savePlan,
    TutorActionCapability.launchPracticeSession,
    TutorActionCapability.launchSongRange,
  },
  Set<String> activeSessionIds = const <String>{},
  Map<String, TutorActionRevisionToken> songRevisions =
      const <String, TutorActionRevisionToken>{},
}) => TutorActionValidationContext(
  now: now,
  availableCapabilities: capabilities,
  activeSessionIds: activeSessionIds,
  songRevisions: songRevisions,
);

TutorProfileUpdateAction _profileAction({DateTime? expiresAt}) =>
    TutorProfileUpdateAction(
      metadata: _metadata(
        capability: TutorActionCapability.updateProfile,
        expiresAt: expiresAt,
      ),
      changes: const <String, Object?>{'preferredTempo': 120},
    );

TutorActionMetadata _metadata({
  required TutorActionCapability capability,
  String clientActionId = 'action-1',
  DateTime? expiresAt,
  TutorActionValidity validity = const TutorActionValidity(),
}) => TutorActionMetadata(
  source: TutorActionSource.modelSuggestion,
  expiresAt: expiresAt ?? DateTime.utc(2026, 8, 5, 11),
  requiredCapability: capability,
  clientActionId: clientActionId,
  validity: validity,
);
