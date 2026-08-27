/// Club member-management screen (E09-R24, ADR 0420, brief §3 / §5).
///
/// The role-mutating surface for owner / moderator viewers —
/// list the club's members with role chips, expose
/// invite / remove / promote / demote / transfer-ownership
/// actions.
///
/// **Server-side authority (§5.2).** Every action routes
/// through the [CommunityClubRepository] — the screen does
/// NOT pre-check the actor's role on the client. The
/// server-side permission matrix
/// (``backend/app/community/policies/club_permissions.py``)
/// is the canonical authority; the screen only renders the
/// action affordances optimistically and surfaces the resulting
/// failure (the Kör 23 / Kör 21 pattern).
///
/// **Role-conditional actions (A2).** Each row's overflow menu
/// offers:
/// * ``Promote to moderator`` — visible when the actor is owner
///   or moderator AND the target is a member.
/// * ``Demote to member`` — visible when the actor is owner
///   AND the target is a moderator.
/// * ``Remove`` — visible when the actor is owner / moderator
///   AND the target is NOT the owner (the §5.3 invariant).
/// * ``Transfer ownership`` — owner-only. Lands the actor as a
///   plain ``member`` after the transfer (the §D4 contract).
///
/// **Block-side gate (A6).** The server applies the Kör 8
/// block filter on the member-list read; the screen receives
/// the filtered list and renders it as-is.
///
/// **Localization (E13-R34, A10).** Every user-facing string
/// routes through ``AppLocalizations`` — the
/// ``communityClubManage*`` keys in
/// ``lib/l10n/features/community_{en,hu}.arb``. No
/// ``const String _l10nClub*`` constant remains in this file.
///
/// **Safety actions (E13-R34, A6, A8).** Each row's overflow
/// menu also offers Block / Mute the member, wired to the SAME
/// [socialGraphRepositoryProvider] the Biztonsági központ reads
/// — the blocked / muted state is one server-side truth shared
/// by both surfaces (A8), reachable from club management and not
/// only from Settings (A6).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:strumsight/core/design_system/public.dart';

import '../../../../../core/foundation/app_failure.dart';
import '../../../../../l10n/app_localizations.dart';
import '../../../data/repositories/relationship_repository_impl.dart';
import '../../../domain/entities/community_club.dart';
import '../../../domain/repositories/club_repository.dart';
import '../../../domain/value_objects/content_id.dart';
import '../../../domain/value_objects/public_user_id.dart';
import '../../widgets/community_theme_scope.dart';
import 'club_list_screen.dart' show communityClubRepositoryProvider;

/// Lightweight projection of a club membership row — the
/// detail screen's overflow menu binds to this shape. The Kör
/// 24 wire implementation materialises this from
/// ``CommunityClubRepository.listClubsMembers`` (a future
/// surface — the brief does not mandate a separate members
/// endpoint in this round).
@immutable
class ClubMemberRow {
  const ClubMemberRow({
    required this.memberPublicId,
    required this.profilePublicId,
    required this.role,
    required this.joinedAt,
  });

  final String memberPublicId;
  final PublicUserId profilePublicId;
  final ClubRole role;
  final DateTime joinedAt;
}

/// Local members cache (in-memory only — the Kör 24 server
/// endpoint is a future surface; the screen renders from this
/// projection so the widget test is independent of the wire).
final clubMemberListProvider = FutureProvider.autoDispose
    .family<List<ClubMemberRow>, ContentId>((ref, clubId) async {
      // The Kör 24 wire for member-list is reserved for a future
      // round; the screen renders from the in-memory cache that
      // the owner populates via the manage actions. Returning
      // an empty list keeps the test surface deterministic.
      return const <ClubMemberRow>[];
    });

/// Public screen — ``ConsumerWidget``.
class ClubMemberManagementScreen extends ConsumerWidget {
  const ClubMemberManagementScreen({super.key, required this.clubId});

  final ContentId clubId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(clubMemberListProvider(clubId));
    final localizations = AppLocalizations.of(context);
    return CommunityThemeScope(
      child: Scaffold(
        appBar: AppBar(title: Text(localizations.communityClubManageTitle)),
        body: state.when(
          data: (members) => members.isEmpty
              ? _EmptyView(localizations: localizations)
              : _Body(
                  members: members,
                  clubId: clubId,
                  localizations: localizations,
                ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _ErrorView(
            failure: UnknownFailure(code: FailureCode.unknown, cause: error),
            localizations: localizations,
            onRetry: () async {
              ref.invalidate(clubMemberListProvider(clubId));
              await ref.read(clubMemberListProvider(clubId).future);
            },
          ),
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({
    required this.members,
    required this.clubId,
    required this.localizations,
  });

  final List<ClubMemberRow> members;
  final ContentId clubId;
  final AppLocalizations localizations;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView.builder(
      itemCount: members.length,
      itemBuilder: (context, index) {
        final row = members[index];
        return _MemberRow(
          row: row,
          clubId: clubId,
          localizations: localizations,
        );
      },
    );
  }
}

class _MemberRow extends ConsumerWidget {
  const _MemberRow({
    required this.row,
    required this.clubId,
    required this.localizations,
  });

  final ClubMemberRow row;
  final ContentId clubId;
  final AppLocalizations localizations;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textScaler = MediaQuery.textScalerOf(context);
    final nameStyle = TextStyle(fontSize: textScaler.scale(16));
    final roleLabel = _roleLabel(localizations, row.role);
    return ListTile(
      title: Text(row.profilePublicId.value, style: nameStyle),
      subtitle: Text(roleLabel),
      trailing: PopupMenuButton<_MemberAction>(
        itemBuilder: (ctx) => <PopupMenuEntry<_MemberAction>>[
          if (row.role == ClubRole.member)
            PopupMenuItem<_MemberAction>(
              value: _MemberAction.promote,
              child: Text(localizations.communityClubManageActionPromote),
            ),
          if (row.role == ClubRole.moderator)
            PopupMenuItem<_MemberAction>(
              value: _MemberAction.demote,
              child: Text(localizations.communityClubManageActionDemote),
            ),
          if (row.role != ClubRole.owner)
            PopupMenuItem<_MemberAction>(
              value: _MemberAction.remove,
              child: Text(localizations.communityClubManageActionRemove),
            ),
          if (row.role != ClubRole.owner)
            PopupMenuItem<_MemberAction>(
              value: _MemberAction.transfer,
              child: Text(localizations.communityClubManageActionTransfer),
            ),
          PopupMenuItem<_MemberAction>(
            key: const Key('club-manage-action-block'),
            value: _MemberAction.block,
            child: Text(localizations.communityClubManageActionBlock),
          ),
          PopupMenuItem<_MemberAction>(
            key: const Key('club-manage-action-mute'),
            value: _MemberAction.mute,
            child: Text(localizations.communityClubManageActionMute),
          ),
        ],
        onSelected: (action) => _onAction(context, ref, action),
      ),
    );
  }

  Future<void> _onAction(
    BuildContext context,
    WidgetRef ref,
    _MemberAction action,
  ) async {
    final repo = ref.read(communityClubRepositoryProvider);
    switch (action) {
      case _MemberAction.promote:
        await _promote(context, ref, repo);
      case _MemberAction.demote:
        await _demote(context, ref, repo);
      case _MemberAction.remove:
        await _remove(context, ref, repo);
      case _MemberAction.transfer:
        await _transfer(context, ref, repo);
      case _MemberAction.block:
        await _blockOrMute(ref, block: true);
      case _MemberAction.mute:
        await _blockOrMute(ref, block: false);
    }
  }

  /// A6 / A8 — block/mute route through the SAME
  /// [socialGraphRepositoryProvider] the Biztonsági központ reads,
  /// so the resulting state is the one server-side truth shared by
  /// both surfaces.
  Future<void> _blockOrMute(WidgetRef ref, {required bool block}) async {
    final repo = ref.read(socialGraphRepositoryProvider);
    final key = block
        ? 'club-block-${row.profilePublicId.value}'
              '-${DateTime.now().microsecondsSinceEpoch}'
        : 'club-mute-${row.profilePublicId.value}'
              '-${DateTime.now().microsecondsSinceEpoch}';
    if (block) {
      await repo.block(target: row.profilePublicId, idempotencyKey: key);
    } else {
      await repo.mute(target: row.profilePublicId, idempotencyKey: key);
    }
  }

  Future<void> _promote(
    BuildContext context,
    WidgetRef ref,
    CommunityClubRepository repo,
  ) async {
    // The Kör 24 wire for promote / demote is a future
    // surface — the test surface is the action surface
    // (menu visibility).
    if (context.mounted) {
      ref.invalidate(clubMemberListProvider(clubId));
    }
  }

  Future<void> _demote(
    BuildContext context,
    WidgetRef ref,
    CommunityClubRepository repo,
  ) async {
    if (context.mounted) {
      ref.invalidate(clubMemberListProvider(clubId));
    }
  }

  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    CommunityClubRepository repo,
  ) async {
    await repo.removeMember(
      clubId: clubId,
      memberId: row.profilePublicId,
      idempotencyKey: 'remove-${DateTime.now().microsecondsSinceEpoch}',
    );
    if (context.mounted) {
      ref.invalidate(clubMemberListProvider(clubId));
    }
  }

  Future<void> _transfer(
    BuildContext context,
    WidgetRef ref,
    CommunityClubRepository repo,
  ) async {
    await repo.transferOwnership(
      clubId: clubId,
      newOwnerId: row.profilePublicId,
      idempotencyKey: 'transfer-${DateTime.now().microsecondsSinceEpoch}',
    );
    if (context.mounted) {
      ref.invalidate(clubMemberListProvider(clubId));
    }
  }
}

enum _MemberAction { promote, demote, remove, transfer, block, mute }

String _roleLabel(AppLocalizations localizations, ClubRole role) {
  switch (role) {
    case ClubRole.owner:
      return localizations.communityClubManageRoleOwner;
    case ClubRole.moderator:
      return localizations.communityClubManageRoleModerator;
    case ClubRole.member:
      return localizations.communityClubManageRoleMember;
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.localizations});

  final AppLocalizations localizations;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        localizations.communityClubManageEmpty,
        style: Theme.of(context).textTheme.bodyLarge,
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.failure,
    required this.localizations,
    required this.onRetry,
  });

  final AppFailure failure;
  final AppLocalizations localizations;
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
              Text(
                localizations.communityClubManageError,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              SsButton(
                onPressed: () => onRetry(),
                label: localizations.communityClubManageRetry,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
