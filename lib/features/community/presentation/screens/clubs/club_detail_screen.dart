/// Club detail screen (E09-R24, ADR 0420, brief §3) +
/// E09-R25 (club feed, pinned posts, club challenges).
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
/// **E09-R25 — four tabs (Feed / Challenges / Members / About).**
/// The single-body layout from Kör 24 is replaced with a
/// ``TabBar`` that swaps between four content surfaces. The
/// Members tab reuses the existing
/// ``club_member_management_screen.dart`` push — the brief
/// §0.0 #3 does not mandate a new members endpoint. The Feed,
/// Challenges, and About tabs build on the screen-local
/// provider pattern (the Kör 24 ``ClubMemberRow`` precedent —
/// see ``club_member_management_screen.dart`` §"Local members
/// cache"). The providers are wired here so the
/// ``ref.invalidate`` calls in ``_leave`` / ``_requestJoin``
/// invalidate them alongside ``clubDetailProvider`` — the
/// §A2 cache-invalidation invariant.
///
/// **Accessibility (A7).** Each action button carries an
/// accessible label; the role-chip carries a ``Semantics``
/// label so a screen reader announces "Owner", "Moderator" or
/// "Member" in one utterance. The TabBar keeps semantic tabs
/// for the screen-reader to enumerate the four surfaces.
///
/// **Localization (E13-R34, A10).** Every user-facing string
/// routes through ``AppLocalizations`` — the ``communityClub*``
/// keys in ``lib/l10n/features/community_{en,hu}.arb``. No
/// ``const String _l10nClub*`` constant remains in this file.
///
/// **Privacy threshold (E13-R34, A3, §0.0.B/B7).** The measured
/// client-side gate is ``myRole`` (`null` = non-member) ×
/// ``visibility``:
/// * `myRole == null` AND `visibility == private` — the screen
///   renders NO club content at all (no name, no description, no
///   tabs) and no join affordance — [_PrivateRestrictedView].
/// * `myRole == null` AND `visibility != private` — the name is
///   shown (needed to identify what the join action targets) plus
///   the join CTA, but no description and no tab content
///   (feed / challenges / members roster stay member-only) —
///   [_JoinPromptView].
/// * `myRole != null` — full content, the four-tab surface.
///
/// This is a CLIENT-SIDE rendering guard on top of whatever
/// ``fetchClub()`` returns — it does not re-derive the backend's
/// permission matrix (SDD §16.3 stays server-authoritative), it
/// only decides what THIS screen paints for a given ``myRole`` /
/// ``visibility`` pair, closing the leak channel a repository
/// that returns more than the SUMMARY placeholder would otherwise
/// open.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:strumsight/core/design_system/public.dart';

import '../../../../../core/foundation/app_failure.dart';
import '../../../../../l10n/app_localizations.dart';
import '../../../domain/entities/community_club.dart';
import '../../../domain/entities/community_post.dart';
import '../../../domain/repositories/club_repository.dart';
import '../../../domain/value_objects/content_id.dart';
import '../../widgets/community_theme_scope.dart';
import 'club_list_screen.dart'
    show communityClubRepositoryProvider, communityClubVisibilityLabel;
import 'club_member_management_screen.dart';

/// FutureProvider for a single club fetch.
final clubDetailProvider = FutureProvider.autoDispose
    .family<CommunityClub, ContentId>((ref, clubId) async {
      final repo = ref.watch(communityClubRepositoryProvider);
      return repo.fetchClub(clubId: clubId);
    });

/// Screen-local provider for the club feed (Kör 25 §0.0 #3 — no
/// new repository methods; the screen builds the projection on
/// top of the existing ``CommunityFeedRepository.clubPinned``
/// stub).
///
/// The provider throws ``UnimplementedError`` in production
/// until the wire-backed implementation lands (a follow-up
/// round) — the Kör 24 ``communityClubRepositoryProvider``
/// pattern. Widget tests override the provider with a stub
/// future that resolves to a fixed ``CommunityPage`` shape.
final clubFeedProvider = FutureProvider.autoDispose
    .family<CommunityPagePlaceholder<CommunityPost>, ContentId>((
      ref,
      clubId,
    ) async {
      throw UnimplementedError(
        'clubFeedProvider is a screen-local seam; override it in tests',
      );
    });

/// Screen-local provider for the club's pinned posts (Kör 25
/// §0.0 #3 — same pattern as [clubFeedProvider]).
final clubPinnedProvider = FutureProvider.autoDispose
    .family<List<CommunityPost>, ContentId>((ref, clubId) async {
      throw UnimplementedError(
        'clubPinnedProvider is a screen-local seam; override it in tests',
      );
    });

/// Screen-local provider for the club's active challenges (Kör
/// 25 §0.0 #3).
final clubChallengesProvider = FutureProvider.autoDispose
    .family<List<CommunityChallengeSummaryPlaceholder>, ContentId>((
      ref,
      clubId,
    ) async {
      throw UnimplementedError(
        'clubChallengesProvider is a screen-local seam; override it in tests',
      );
    });

/// Lightweight projection of a single club challenge row —
/// binds to the ``clubChallengesProvider`` future shape. The
/// full ``CommunityChallengeDefinition`` entity lives in
/// ``community_challenge.dart``; this placeholder is the
/// screen-local minimum the tab needs to render.
@immutable
class CommunityChallengeSummaryPlaceholder {
  const CommunityChallengeSummaryPlaceholder({
    required this.challengePublicId,
    required this.metric,
    required this.difficulty,
    required this.startsAt,
    required this.endsAt,
  });

  final String challengePublicId;
  final String metric;
  final int difficulty;
  final DateTime startsAt;
  final DateTime endsAt;
}

/// Lightweight projection of a single page of community content
/// — the screen-local placeholder for the feed tab. Mirrors
/// the production ``CommunityPage<T>`` shape from
/// ``community_page.dart`` so the wire-backed implementation
/// (a follow-up round) can plug in without a screen-side
/// refactor.
@immutable
class CommunityPagePlaceholder<T> {
  const CommunityPagePlaceholder({required this.items});

  final List<T> items;
}

/// Public screen — ``ConsumerWidget`` so the test surface is the
/// ``ProviderScope`` override of the
/// ``communityClubRepositoryProvider`` (the Kör 23 / Kör 21
/// pattern) AND the screen-local feed / pinned / challenges
/// providers (the Kör 25 §0.0 #3 precedent).
class ClubDetailScreen extends ConsumerWidget {
  const ClubDetailScreen({super.key, required this.clubId});

  final ContentId clubId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(clubDetailProvider(clubId));
    final localizations = AppLocalizations.of(context);

    return CommunityThemeScope(
      child: state.when(
        data: (club) => _buildForClub(context, ref, club, localizations),
        loading: () => Scaffold(
          appBar: AppBar(title: Text(localizations.communityClubDetailTitle)),
          body: const Center(child: CircularProgressIndicator()),
        ),
        error: (error, _) => Scaffold(
          appBar: AppBar(title: Text(localizations.communityClubDetailTitle)),
          body: _ErrorView(
            failure: UnknownFailure(code: FailureCode.unknown, cause: error),
            localizations: localizations,
            onRetry: () async {
              ref.invalidate(clubDetailProvider(clubId));
              await ref.read(clubDetailProvider(clubId).future);
            },
          ),
        ),
      ),
    );
  }

  /// A3 gate (§0.0.B/B7): dispatches on ``myRole`` × ``visibility``
  /// BEFORE any club content reaches a widget tree.
  Widget _buildForClub(
    BuildContext context,
    WidgetRef ref,
    CommunityClub club,
    AppLocalizations localizations,
  ) {
    final role = club.myRole;
    final isMember = role != null;
    final isPrivateNonMember =
        !isMember && club.visibility == ClubVisibility.private;

    if (isPrivateNonMember) {
      // Below the threshold — NO club content, no join CTA.
      return Scaffold(
        appBar: AppBar(title: Text(localizations.communityClubDetailTitle)),
        body: _PrivateRestrictedView(localizations: localizations),
      );
    }

    if (!isMember) {
      // On the threshold — name + join CTA only, no tab content.
      return Scaffold(
        appBar: AppBar(title: Text(localizations.communityClubDetailTitle)),
        body: _JoinPromptView(
          club: club,
          localizations: localizations,
          onJoin: () => _requestJoin(context, ref),
        ),
      );
    }

    // Above the threshold — full content, the four-tab surface.
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(localizations.communityClubDetailTitle),
          bottom: TabBar(
            tabs: <Widget>[
              Tab(text: localizations.communityClubTabFeed),
              Tab(text: localizations.communityClubTabChallenges),
              Tab(text: localizations.communityClubTabMembers),
              Tab(text: localizations.communityClubTabAbout),
            ],
          ),
        ),
        body: _Body(club: club, clubId: clubId, localizations: localizations),
      ),
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
      ref.invalidate(clubFeedProvider(clubId));
      ref.invalidate(clubPinnedProvider(clubId));
      ref.invalidate(clubChallengesProvider(clubId));
    }
  }
}

/// The "below the threshold" cell (A3, §0.0.B/B7): non-member,
/// `private` club. Renders NO club content — not even the name —
/// and no join affordance (private joins are invite-only).
class _PrivateRestrictedView extends StatelessWidget {
  const _PrivateRestrictedView({required this.localizations});

  final AppLocalizations localizations;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.lock_outline, size: 40, color: theme.hintColor),
            const SizedBox(height: 16),
            Text(
              localizations.communityClubPrivateRestrictedTitle,
              key: const Key('club-private-restricted-title'),
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              localizations.communityClubPrivateRestrictedBody,
              key: const Key('club-private-restricted-body'),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// The "on the threshold" cell (A3, §0.0.B/B7): non-member,
/// `discoverable` / `public` club. Shows the club name (needed to
/// identify what the join action targets) and the join CTA — but
/// NO description and no tab content; the feed, the challenges and
/// the member roster stay member-only.
class _JoinPromptView extends StatelessWidget {
  const _JoinPromptView({
    required this.club,
    required this.localizations,
    required this.onJoin,
  });

  final CommunityClub club;
  final AppLocalizations localizations;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final textScaler = MediaQuery.textScalerOf(context);
    final nameStyle = TextStyle(
      fontSize: textScaler.scale(22),
      fontWeight: FontWeight.bold,
    );
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              club.name,
              key: const Key('club-join-prompt-name'),
              style: nameStyle,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              localizations.communityClubJoinToSeeMore,
              key: const Key('club-join-prompt-body'),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            SsButton(
              onPressed: onJoin,
              label: localizations.communityClubDetailJoin,
            ),
          ],
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({
    required this.club,
    required this.clubId,
    required this.localizations,
  });

  final CommunityClub club;
  final ContentId clubId;
  final AppLocalizations localizations;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textScaler = MediaQuery.textScalerOf(context);
    final nameStyle = TextStyle(
      fontSize: textScaler.scale(22),
      fontWeight: FontWeight.bold,
    );
    final bodyStyle = TextStyle(fontSize: textScaler.scale(16));
    final role = club.myRole;
    final roleLabel = _roleLabel(localizations, role);
    final canLeave = role != null;
    final canManage = role == ClubRole.owner || role == ClubRole.moderator;
    return Column(
      children: <Widget>[
        // Capped + internally scrollable so a long name/description at a
        // large system text-scale setting cannot squeeze the TabBarView
        // below to nothing or overflow the Column (measured, real —
        // L517: the textScaler 2.0 golden frame catches exactly this
        // class of layout bug).
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.4,
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(club.name, style: nameStyle),
                  const SizedBox(height: 8),
                  Text(club.description, style: bodyStyle),
                  const SizedBox(height: 16),
                  Semantics(
                    label: localizations.communityClubDetailRoleSemanticLabel(
                      roleLabel,
                    ),
                    child: Chip(label: Text(roleLabel)),
                  ),
                  const SizedBox(height: 16),
                  if (canLeave)
                    SsButton(
                      variant: SsButtonVariant.secondary,
                      onPressed: () => _leave(context, ref),
                      label: localizations.communityClubDetailLeave,
                    ),
                  if (canManage)
                    SsButton(
                      variant: SsButtonVariant.secondary,
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                ClubMemberManagementScreen(clubId: clubId),
                          ),
                        );
                      },
                      label: localizations.communityClubDetailManage,
                    ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: TabBarView(
            children: <Widget>[
              _ClubFeedTab(clubId: clubId, localizations: localizations),
              _ClubChallengesTab(clubId: clubId, localizations: localizations),
              _ClubMembersTab(localizations: localizations),
              _ClubAboutTab(club: club, localizations: localizations),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _leave(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(communityClubRepositoryProvider);
    await repo.leave(
      clubId: clubId,
      idempotencyKey: 'leave-${DateTime.now().microsecondsSinceEpoch}',
    );
    if (context.mounted) {
      // §A2 — the cache-invalidation invariant. After the caller
      // leaves the club, all four tab's screen-local providers
      // must drop their cached rows so the "only-club" content
      // disappears immediately. The Kör 24 precedent invalidates
      // ``clubDetailProvider`` only; we extend that to the
      // screen-local providers added in E09-R25.
      _invalidateClubContentProviders(ref);
    }
  }

  void _invalidateClubContentProviders(WidgetRef ref) {
    ref.invalidate(clubDetailProvider(clubId));
    ref.invalidate(clubFeedProvider(clubId));
    ref.invalidate(clubPinnedProvider(clubId));
    ref.invalidate(clubChallengesProvider(clubId));
  }
}

/// Feed tab — pinned posts at the top, then recent posts.
class _ClubFeedTab extends ConsumerWidget {
  const _ClubFeedTab({required this.clubId, required this.localizations});

  final ContentId clubId;
  final AppLocalizations localizations;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pinnedAsync = ref.watch(clubPinnedProvider(clubId));
    final feedAsync = ref.watch(clubFeedProvider(clubId));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text(
          localizations.communityClubFeedPinnedHeader,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ...pinnedAsync.when(
          data: (pinned) => pinned.isEmpty
              ? <Widget>[Text(localizations.communityClubFeedEmpty)]
              : <Widget>[
                  for (final post in pinned)
                    ListTile(title: Text(post.body ?? '')),
                ],
          loading: () => const <Widget>[CircularProgressIndicator()],
          error: (_, _) => <Widget>[Text(localizations.communityClubFeedEmpty)],
        ),
        const SizedBox(height: 16),
        Text(
          localizations.communityClubFeedRecentHeader,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ...feedAsync.when(
          data: (feed) => feed.items.isEmpty
              ? <Widget>[Text(localizations.communityClubFeedEmpty)]
              : <Widget>[
                  for (final post in feed.items)
                    ListTile(title: Text(post.body ?? '')),
                ],
          loading: () => const <Widget>[CircularProgressIndicator()],
          error: (_, _) => <Widget>[Text(localizations.communityClubFeedEmpty)],
        ),
      ],
    );
  }
}

/// Challenges tab — active challenges of the club.
class _ClubChallengesTab extends ConsumerWidget {
  const _ClubChallengesTab({required this.clubId, required this.localizations});

  final ContentId clubId;
  final AppLocalizations localizations;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final challengesAsync = ref.watch(clubChallengesProvider(clubId));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        ...challengesAsync.when(
          data: (challenges) => challenges.isEmpty
              ? <Widget>[Text(localizations.communityClubChallengesEmpty)]
              : <Widget>[
                  for (final c in challenges)
                    ListTile(
                      title: Text(
                        '${c.metric} • '
                        '${localizations.communityClubChallengesDifficultyPrefix} '
                        '${c.difficulty}',
                      ),
                      subtitle: Text(
                        '${c.startsAt.toIso8601String()} → ${c.endsAt.toIso8601String()}',
                      ),
                    ),
                ],
          loading: () => const <Widget>[CircularProgressIndicator()],
          error: (_, _) => <Widget>[
            Text(localizations.communityClubChallengesEmpty),
          ],
        ),
      ],
    );
  }
}

/// Members tab — the screen-local placeholder; the production
/// surface reuses the ``ClubMemberManagementScreen`` push from
/// the Kör 24 detail screen.
class _ClubMembersTab extends ConsumerWidget {
  const _ClubMembersTab({required this.localizations});

  final AppLocalizations localizations;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The Members tab defers the read to the Kör 24
    // ``clubMemberManagement_screen`` push so this round does
    // not need a new repository method (the brief §0.0 #3
    // structural precedent). The placeholder body just nudges
    // the user to the manage screen.
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: Text(
          localizations.communityClubMembersTabHint,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

/// About tab — the club's description, owner, and visibility.
class _ClubAboutTab extends ConsumerWidget {
  const _ClubAboutTab({required this.club, required this.localizations});

  final CommunityClub club;
  final AppLocalizations localizations;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visibilityLabel = communityClubVisibilityLabel(
      localizations,
      club.visibility,
    );
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            club.description.isEmpty
                ? localizations.communityClubAboutEmpty
                : club.description,
          ),
          const SizedBox(height: 12),
          Chip(label: Text(visibilityLabel)),
        ],
      ),
    );
  }
}

String _roleLabel(AppLocalizations localizations, ClubRole? role) {
  if (role == null) return localizations.communityClubDetailRoleNone;
  switch (role) {
    case ClubRole.owner:
      return localizations.communityClubDetailRoleOwner;
    case ClubRole.moderator:
      return localizations.communityClubDetailRoleModerator;
    case ClubRole.member:
      return localizations.communityClubDetailRoleMember;
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
                localizations.communityClubDetailError,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              SsButton(
                onPressed: () => onRetry(),
                label: localizations.communityClubDetailRetry,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
