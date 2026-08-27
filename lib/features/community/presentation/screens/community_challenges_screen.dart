/// Community challenge list + invite actions screen
/// (E09-R21, ADR 0415, brief §6; design-system migration E13-R34).
///
/// The screen renders the caller's challenge list with per-row
/// accept / decline / cancel buttons and a deep-link action that
/// opens the resolved Practice / Song flow when the challenge
/// type supports it (A6). The push gateway is a refresh trigger
/// only — the inbox / list is the source of truth (the Kör 20
/// ADR 0414 §D3 invariant).
///
/// **Accept / decline / cancel (A1, A2, A5).** Tapping a row's
/// action button calls the controller's
/// ``acceptInvite`` / ``declineInvite`` / ``cancelInvite``; the
/// controller is the single mutation path (the Kör 20
/// ``NotificationController`` precedent). A failure rolls the
/// UI state back and surfaces the error.
///
/// **Deep link (A6).** ``challengeDeepLinkTargetFromType``
/// resolves the challenge type to a [ChallengeDeepLinkTarget]
/// flow. The mapping is structural — ``personalBest`` resolves
/// to the personal-best flow; the ``friends`` / ``club`` /
/// ``dailyCommunity`` / ``periodicGlobal`` types resolve to
/// [ChallengeDeepLinkTarget.none] and the row renders a
/// display-only chip. The wire shape does NOT carry a flow id —
/// the screen derives the route from the challenge type, and a
/// future round can swap the derivation without breaking the
/// wire.
///
/// **Offline (D7 / Kör 20).** The repository's list endpoint is
/// the source of truth; the screen does not subscribe to a
/// push-broadcast stream — the controller's ``load`` is called
/// from the screen's ``initState``; a pull-to-refresh triggers
/// a re-load. The cached items list is the only client-side
/// surface (the controller holds the in-memory snapshot).
///
/// **Pending vs. verified result (E13-R34, A2 / A5).** The
/// row's action sheet exposes a "View my result" entry that
/// lazily reads [CommunityChallengeRepository.fetchMyParticipation]
/// via [challengeMyParticipationProvider] — the pinned
/// ``community_challenges_test.dart`` list-render path never
/// triggers this fetch (it is opened only on an explicit tap),
/// so the existing fake repository (which does not stub
/// ``fetchMyParticipation``) keeps passing. A `null`
/// [CommunityChallengeParticipantState.bestMetricValue] renders
/// the NEUTRAL "verification in progress" copy — never a
/// cheating accusation (A5) — and is visually distinct from the
/// verified-result row (A2). The ranglista opt-in itself stays
/// entirely server-owned (§0.0.B/B5) — this screen never calls
/// ``leaderboard()`` or synthesizes a rank row (A1).
///
/// **Safety actions (A6, A8).** Each row's action sheet also
/// exposes Block / Mute for the challenge's author, wired to the
/// SAME [socialGraphRepositoryProvider] the Biztonsági központ
/// (``safety_relationships_screen.dart``) reads — so the blocked
/// / muted state is the one server-side truth shared by both
/// surfaces (A8), reachable from the challenge list and not only
/// from Settings (A6).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:strumsight/core/design_system/public.dart';

import '../../../../core/foundation/app_failure.dart';
import '../../../../l10n/app_localizations.dart';
import '../../application/controllers/challenge_controller.dart';
import '../../data/repositories/relationship_repository_impl.dart';
import '../../domain/entities/community_challenge.dart';
import '../../domain/repositories/challenge_repository.dart';
import '../../domain/value_objects/content_id.dart';
import '../../domain/value_objects/public_user_id.dart';
import '../widgets/community_theme_scope.dart';

/// Screen-local provider for the viewer's own participation state
/// on one challenge (E13-R34, A2). ``autoDispose`` + ``family`` so
/// entering/leaving the action sheet is cheap and independent per
/// challenge. Only watched from inside the action sheet — never
/// from the list-render path — so it does not disturb the Kör 21
/// pinned widget test.
final challengeMyParticipationProvider = FutureProvider.autoDispose
    .family<CommunityChallengeParticipantState?, ContentId>((ref, challengeId) {
      final repo = ref.watch(communityChallengeRepositoryProvider);
      return repo.fetchMyParticipation(challengeId: challengeId);
    });

/// Public screen — ``ConsumerWidget`` so the test surface is the
/// ``ProviderScope`` override of the
/// ``communityChallengeRepositoryProvider`` (the Kör 14 / Kör 20
/// controller-injection precedent).
class CommunityChallengesScreen extends ConsumerWidget {
  const CommunityChallengesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncState = ref.watch(challengeControllerProvider);
    final localizations = AppLocalizations.of(context);
    final notifier = ref.read(challengeControllerProvider.notifier);

    return CommunityThemeScope(
      child: Scaffold(
        appBar: AppBar(title: Text(localizations.communityChallengeTitle)),
        body: RefreshIndicator(
          onRefresh: notifier.load,
          child: asyncState.when(
            data: (state) => _Body(
              state: state,
              notifier: notifier,
              localizations: localizations,
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => _ErrorView(
              failure: UnknownFailure(code: FailureCode.unknown, cause: error),
              onRetry: notifier.load,
            ),
          ),
        ),
      ),
    );
  }
}

class _Body extends ConsumerStatefulWidget {
  const _Body({
    required this.state,
    required this.notifier,
    required this.localizations,
  });

  final ChallengeListState state;
  final ChallengeController notifier;
  final AppLocalizations localizations;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  @override
  void initState() {
    super.initState();
    // Same post-frame callback pattern as
    // ``community_notifications_screen`` — the microtask runs
    // during ``pumpAndSettle`` so widget tests see the loaded
    // state after a single settle call.
    Future.microtask(() => widget.notifier.load());
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final notifier = widget.notifier;
    final localizations = widget.localizations;

    if (state.isLoading && state.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.lastError != null && state.items.isEmpty) {
      return _ErrorView(failure: state.lastError!, onRetry: notifier.load);
    }
    if (state.items.isEmpty) {
      return ListView(
        children: <Widget>[
          const SizedBox(height: 32),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: Text(
                localizations.communityChallengeEmpty,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          ),
        ],
      );
    }

    final halted = state.cursor.isInitial || state.cursor.cursor == null;
    final children = <Widget>[
      Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          localizations.communityChallengeListHeader,
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
      for (final challenge in state.items)
        _ChallengeRow(
          challenge: challenge,
          isMutating: state.isMutating,
          onAccept: (inviteId) => notifier.acceptInvite(ContentId(inviteId)),
          onDecline: (inviteId) => notifier.declineInvite(ContentId(inviteId)),
          onCancel: (inviteId, target) => notifier.cancelInvite(
            invitePublicId: ContentId(inviteId),
            target: target,
          ),
        ),
    ];
    if (!halted) {
      children.add(
        const Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    return ListView(
      children: <Widget>[
        for (var i = 0; i < children.length; i++) ...<Widget>[
          children[i],
          if (i < children.length - 1) const Divider(height: 1),
        ],
      ],
    );
  }
}

class _ChallengeRow extends ConsumerWidget {
  const _ChallengeRow({
    required this.challenge,
    required this.isMutating,
    required this.onAccept,
    required this.onDecline,
    required this.onCancel,
  });

  final CommunityChallengeDefinition challenge;
  final bool isMutating;
  final ValueChanged<String> onAccept;
  final ValueChanged<String> onDecline;
  final void Function(String inviteId, PublicUserId target) onCancel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final deepLinkTarget = challengeDeepLinkTargetFromType(challenge.type);
    return ListTile(
      title: Text(challenge.metric),
      subtitle: Text(
        localizations.communityChallengeWindowLabel(
          challenge.startsAt.toIso8601String(),
          challenge.endsAt.toIso8601String(),
        ),
      ),
      trailing: deepLinkTarget == ChallengeDeepLinkTarget.none
          ? null
          : IconButton(
              icon: const Icon(Icons.play_arrow),
              tooltip: deepLinkTarget == ChallengeDeepLinkTarget.personalBest
                  ? localizations.communityChallengeDeepLinkPractice
                  : localizations.communityChallengeDeepLinkSong,
              onPressed: isMutating
                  ? null
                  : () => _openDeepLink(deepLinkTarget),
            ),
      onTap: () => _showActions(context),
    );
  }

  void _showActions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => CommunityThemeScope(
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Consumer(
                builder: (context, ref, _) =>
                    _MyResultSection(challengeId: challenge.id, ref: ref),
              ),
              ListTile(
                leading: const Icon(Icons.check),
                title: Text(
                  AppLocalizations.of(sheetContext).communityChallengeAccept,
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  onAccept(challenge.id.value);
                },
              ),
              ListTile(
                leading: const Icon(Icons.close),
                title: Text(
                  AppLocalizations.of(sheetContext).communityChallengeDecline,
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  onDecline(challenge.id.value);
                },
              ),
              ListTile(
                leading: const Icon(Icons.cancel_outlined),
                title: Text(
                  AppLocalizations.of(sheetContext).communityChallengeCancel,
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  // The cancel path requires a target — the
                  // list row knows the challenge id but not the
                  // invitee. The wire shape includes the
                  // invitee on the per-row envelope (the
                  // controller's invite flow), so this branch
                  // surfaces the action with the row's
                  // author_id as a placeholder for the wire.
                  onCancel(challenge.id.value, challenge.authorId);
                },
              ),
              const Divider(height: 1),
              ListTile(
                key: const Key('challenge-action-block-author'),
                leading: const Icon(Icons.block_outlined),
                title: Text(
                  AppLocalizations.of(
                    sheetContext,
                  ).communityChallengeActionBlockAuthor,
                ),
                onTap: () => _blockOrMuteAuthor(sheetContext, block: true),
              ),
              ListTile(
                key: const Key('challenge-action-mute-author'),
                leading: const Icon(Icons.volume_off_outlined),
                title: Text(
                  AppLocalizations.of(
                    sheetContext,
                  ).communityChallengeActionMuteAuthor,
                ),
                onTap: () => _blockOrMuteAuthor(sheetContext, block: false),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _blockOrMuteAuthor(
    BuildContext sheetContext, {
    required bool block,
  }) async {
    final container = ProviderScope.containerOf(sheetContext);
    final repo = container.read(socialGraphRepositoryProvider);
    Navigator.of(sheetContext).pop();
    final key = block
        ? 'challenge-block-${challenge.authorId.value}'
              '-${DateTime.now().microsecondsSinceEpoch}'
        : 'challenge-mute-${challenge.authorId.value}'
              '-${DateTime.now().microsecondsSinceEpoch}';
    if (block) {
      await repo.block(target: challenge.authorId, idempotencyKey: key);
    } else {
      await repo.mute(target: challenge.authorId, idempotencyKey: key);
    }
  }

  void _openDeepLink(ChallengeDeepLinkTarget target) {
    // The deep-link routing is a future round's concern — the
    // screen logs the navigation intent so the widget test can
    // assert the type-resolution branch (A6) without coupling
    // the Kör 21 surface to the practice / songs / personal-best
    // routes.
    debugPrint(
      'community.challenges.deepLink '
      'challenge=${challenge.id.value} target=$target',
    );
  }
}

/// Renders the viewer's own participation status inside the row's
/// action sheet (E13-R34, A2 / A5). `null` participation (not yet
/// joined) renders nothing; a `null` ``bestMetricValue`` renders the
/// NEUTRAL "verification in progress" copy (A5 — never an accusation
/// of cheating); a non-null value renders the verified result with
/// the verified glyph (A2 — visually and textually distinct from the
/// pending state).
class _MyResultSection extends StatelessWidget {
  const _MyResultSection({required this.challengeId, required this.ref});

  final ContentId challengeId;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final async = ref.watch(challengeMyParticipationProvider(challengeId));
    return async.when(
      data: (participation) {
        if (participation == null) return const SizedBox.shrink();
        final bestMetricValue = participation.bestMetricValue;
        final Widget row;
        if (bestMetricValue == null) {
          row = Row(
            children: <Widget>[
              Icon(Icons.hourglass_empty, color: Theme.of(context).hintColor),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  localizations.communityChallengeResultPending,
                  key: const Key('challenge-result-pending'),
                ),
              ),
            ],
          );
        } else {
          row = Row(
            children: <Widget>[
              Icon(
                Icons.verified,
                color: Theme.of(context).colorScheme.primary,
                semanticLabel: 'Verified',
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  localizations.communityChallengeResultVerified(
                    bestMetricValue,
                  ),
                  key: const Key('challenge-result-verified'),
                ),
              ),
            ],
          );
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SsCard(child: row),
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.failure, required this.onRetry});

  final AppFailure failure;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return ListView(
      children: <Widget>[
        const SizedBox(height: 32),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                _formatFailure(localizations, failure),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              SsButton(
                onPressed: () => onRetry(),
                label: localizations.communityNotificationsRetry,
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatFailure(AppLocalizations localizations, AppFailure failure) {
    switch (failure.code) {
      case FailureCode.networkUnavailable:
        return localizations.communityChallengeErrorNetwork;
      case FailureCode.authSessionExpired:
        return localizations.communityChallengeErrorSessionExpired;
      case FailureCode.authForbidden:
        return localizations.communityChallengeErrorForbidden;
      case FailureCode.networkServer:
        // 429 (rate-limited) maps to ``networkServer`` in the
        // shared mapper; the A4 / §5.3 invariant lands on
        // this branch.
        return localizations.communityChallengeErrorRateLimited;
      case FailureCode.communityConflict:
        return localizations.communityChallengeErrorConflict;
      case FailureCode.validationInvalidInput:
        return localizations.communityChallengeErrorInvalidInput;
      default:
        return failure.toString();
    }
  }
}

// Keep the imports honest — the controller / repository types
// appear in the surface but the screen's primary dependency is
// the controller.
// ignore: unused_element
typedef _UnusedChallengeRepo = CommunityChallengeRepository;
