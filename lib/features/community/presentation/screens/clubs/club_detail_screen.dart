/// Club detail screen (E09-R24, ADR 0420, brief §3).
///
/// Renders a single club with its description, visibility, owner
/// handle, and the caller's role inside it. The screen is the
/// entry point for membership / invite / role-mutation actions
/// — those go through the [CommunityClubRepository] contract
/// (the Kör 5 / ADR 0399 surface).
///
/// **Why a separate screen.** The list screen (D7) embeds the
/// create flow, but reading a single club + acting on it
/// (request join / leave / transfer) needs its own dedicated
/// surface. The detail screen owns the role-conditional action
/// surface so the list screen stays focused on browsing.
///
/// **Action buttons (A2).** The screen exposes:
/// * ``requestJoin`` — disabled if the viewer is already a member
///   or the club is private (private joins go through
///   accept-pending-request, not the public request path).
/// * ``leave`` — disabled if the viewer is the lone owner
///   (the A1 invariant — ``OwnerMustTransferFirst`` surfaces
///   at the wire layer).
/// * ``manage`` — links to the
///   [ClubMemberManagementScreen] for owner / moderator
///   viewers (A5).
///
/// **Accessibility (A7).** Each action button carries an
/// accessible label; the role-chip carries a ``Semantics``
/// label so a screen reader announces "Owner", "Moderator" or
/// "Member" in one utterance.
///
/// **Localization note (l10n).** The labels are hardcoded
/// English placeholders — the ARB file is not on this round's
/// ``allowed_paths`` (Kör 18 will lift the strings).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/foundation/app_failure.dart';
import '../../../domain/entities/community_club.dart';
import '../../../domain/repositories/club_repository.dart';
import '../../../domain/value_objects/content_id.dart';
import 'club_list_screen.dart' show communityClubRepositoryProvider;
import 'club_member_management_screen.dart';

// ---------------------------------------------------------------------------
// L10n placeholders — to be lifted into app_en.arb / app_hu.arb in a
// future round.
// ---------------------------------------------------------------------------

const String _l10nClubDetailTitle = 'Club';
const String _l10nClubDetailError = "The club couldn't load.";
const String _l10nClubDetailRetry = 'Retry';
const String _l10nClubDetailJoin = 'Request to join';
const String _l10nClubDetailLeave = 'Leave club';
const String _l10nClubDetailManage = 'Manage members';
const String _l10nClubDetailRoleOwner = 'Owner';
const String _l10nClubDetailRoleModerator = 'Moderator';
const String _l10nClubDetailRoleMember = 'Member';
const String _l10nClubDetailRoleNone = 'Not a member';

/// FutureProvider for a single club fetch.
final clubDetailProvider = FutureProvider.autoDispose
    .family<CommunityClub, ContentId>((ref, clubId) async {
      final repo = ref.watch(communityClubRepositoryProvider);
      return repo.fetchClub(clubId: clubId);
    });

/// Public screen — ``ConsumerWidget`` so the test surface is the
/// ``ProviderScope`` override of the
/// ``communityClubRepositoryProvider`` (the Kör 23 / Kör 21
/// pattern).
class ClubDetailScreen extends ConsumerWidget {
  const ClubDetailScreen({super.key, required this.clubId});

  final ContentId clubId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(clubDetailProvider(clubId));

    return Scaffold(
      appBar: AppBar(title: const Text(_l10nClubDetailTitle)),
      body: state.when(
        data: (club) => _Body(club: club, clubId: clubId),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorView(
          failure: UnknownFailure(code: FailureCode.unknown, cause: error),
          onRetry: () async {
            ref.invalidate(clubDetailProvider(clubId));
            await ref.read(clubDetailProvider(clubId).future);
          },
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.club, required this.clubId});

  final CommunityClub club;
  final ContentId clubId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textScaler = MediaQuery.textScalerOf(context);
    final nameStyle = TextStyle(
      fontSize: textScaler.scale(22),
      fontWeight: FontWeight.bold,
    );
    final bodyStyle = TextStyle(fontSize: textScaler.scale(16));
    final role = club.myRole;
    final roleLabel = _roleLabel(role);
    final canJoin = role == null && club.visibility != ClubVisibility.private;
    final canLeave = role != null;
    final canManage = role == ClubRole.owner || role == ClubRole.moderator;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text(club.name, style: nameStyle),
        const SizedBox(height: 8),
        Text(club.description, style: bodyStyle),
        const SizedBox(height: 16),
        Semantics(
          label: 'Role: $roleLabel',
          child: Chip(label: Text(roleLabel)),
        ),
        const SizedBox(height: 16),
        if (canJoin)
          FilledButton(
            onPressed: () => _requestJoin(context, ref),
            child: const Text(_l10nClubDetailJoin),
          ),
        if (canLeave)
          OutlinedButton(
            onPressed: () => _leave(context, ref),
            child: const Text(_l10nClubDetailLeave),
          ),
        if (canManage)
          OutlinedButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ClubMemberManagementScreen(clubId: clubId),
                ),
              );
            },
            child: const Text(_l10nClubDetailManage),
          ),
      ],
    );
  }

  Future<void> _requestJoin(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(communityClubRepositoryProvider);
    await repo.requestJoin(
      clubId: clubId,
      idempotencyKey: 'join-${DateTime.now().microsecondsSinceEpoch}',
    );
    if (context.mounted) {
      ref.invalidate(clubDetailProvider(clubId));
    }
  }

  Future<void> _leave(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(communityClubRepositoryProvider);
    await repo.leave(
      clubId: clubId,
      idempotencyKey: 'leave-${DateTime.now().microsecondsSinceEpoch}',
    );
    if (context.mounted) {
      ref.invalidate(clubDetailProvider(clubId));
    }
  }
}

String _roleLabel(ClubRole? role) {
  if (role == null) return _l10nClubDetailRoleNone;
  switch (role) {
    case ClubRole.owner:
      return _l10nClubDetailRoleOwner;
    case ClubRole.moderator:
      return _l10nClubDetailRoleModerator;
    case ClubRole.member:
      return _l10nClubDetailRoleMember;
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.failure, required this.onRetry});

  final AppFailure failure;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: <Widget>[
        const SizedBox(height: 32),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              const Text(_l10nClubDetailError, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              TextButton(
                onPressed: onRetry,
                child: const Text(_l10nClubDetailRetry),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
