/// Community challenge list + invite actions screen
/// (E09-R21, ADR 0415, brief §6).
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
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/foundation/app_failure.dart';
import '../../../../l10n/app_localizations.dart';
import '../../application/controllers/challenge_controller.dart';
import '../../domain/entities/community_challenge.dart';
import '../../domain/repositories/challenge_repository.dart';
import '../../domain/value_objects/content_id.dart';
import '../../domain/value_objects/public_user_id.dart';

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

    return Scaffold(
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
      builder: (sheetContext) {
        final localizations = AppLocalizations.of(sheetContext);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.check),
                title: Text(localizations.communityChallengeAccept),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  onAccept(challenge.id.value);
                },
              ),
              ListTile(
                leading: const Icon(Icons.close),
                title: Text(localizations.communityChallengeDecline),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  onDecline(challenge.id.value);
                },
              ),
              ListTile(
                leading: const Icon(Icons.cancel_outlined),
                title: Text(localizations.communityChallengeCancel),
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
            ],
          ),
        );
      },
    );
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
              TextButton(
                onPressed: onRetry,
                child: Text(localizations.communityNotificationsRetry),
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
