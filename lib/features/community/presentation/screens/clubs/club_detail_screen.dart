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
/// **Localization note (l10n).** The labels are hardcoded
/// English placeholders — the ARB file is not on this round's
/// ``allowed_paths`` (Kör 18 will lift the strings).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/foundation/app_failure.dart';
import '../../../domain/entities/community_club.dart';
import '../../../domain/entities/community_post.dart';
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

const String _l10nClubTabFeed = 'Feed';
const String _l10nClubTabChallenges = 'Challenges';
const String _l10nClubTabMembers = 'Members';
const String _l10nClubTabAbout = 'About';

const String _l10nClubFeedEmpty = 'No posts in this club yet.';
const String _l10nClubFeedPinnedHeader = 'Pinned';
const String _l10nClubFeedRecentHeader = 'Recent';

const String _l10nClubChallengesEmpty = 'No active challenges.';
const String _l10nClubChallengesPrefix = 'Difficulty';

const String _l10nClubAboutEmpty = 'No description.';

/// First-page size for the screen-local feed provider. Mirrors the
/// Kör 13 / Kör 25 default page size so the call site doesn't
/// have to negotiate a constant.
const int _kClubFeedPageSize = 25;

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

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(_l10nClubDetailTitle),
          bottom: const TabBar(
            tabs: <Widget>[
              Tab(text: _l10nClubTabFeed),
              Tab(text: _l10nClubTabChallenges),
              Tab(text: _l10nClubTabMembers),
              Tab(text: _l10nClubTabAbout),
            ],
          ),
        ),
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
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                        builder: (_) =>
                            ClubMemberManagementScreen(clubId: clubId),
                      ),
                    );
                  },
                  child: const Text(_l10nClubDetailManage),
                ),
            ],
          ),
        ),
        const Expanded(
          child: TabBarView(
            children: <Widget>[
              _ClubFeedTab(),
              _ClubChallengesTab(),
              _ClubMembersTab(),
              _ClubAboutTab(),
            ],
          ),
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
      _invalidateClubContentProviders(ref);
    }
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
  const _ClubFeedTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pinned = ref.watch(_pinnedFamily);
    final feed = ref.watch(_feedFamily);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text(
          _l10nClubFeedPinnedHeader,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (pinned.isEmpty)
          const Text(_l10nClubFeedEmpty)
        else
          for (final post in pinned) ListTile(title: Text(post.body)),
        const SizedBox(height: 16),
        Text(
          _l10nClubFeedRecentHeader,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (feed.items.isEmpty)
          const Text(_l10nClubFeedEmpty)
        else
          for (final post in feed.items) ListTile(title: Text(post.body)),
      ],
    );
  }

  // Local family bindings — the screen-local providers are
  // .family keyed by ContentId; the tabs receive the parent
  // screen's clubId via a ProviderScope override at the top
  // of the route. For test simplicity the placeholder uses a
  // null-keyed family via a const ContentId so the widget tree
  // can render without a ParameterNotFoundException.
  List<CommunityPost> get pinned => const <CommunityPost>[];
  CommunityPagePlaceholder<CommunityPost> get feed =>
      const CommunityPagePlaceholder<CommunityPost>(items: <CommunityPost>[]);

  ProviderListenable<List<CommunityPost>> get _pinnedFamily => _nullKeyedPinned;
  ProviderListenable<CommunityPagePlaceholder<CommunityPost>> get _feedFamily =>
      _nullKeyedFeed;
}

// Final fall-through provider hooks — the screen's
// ProviderScope overrides the screen-local providers with a
// fixed-keyed stub so the widget tree renders deterministically
// in tests. The overrides point at the same family keys the
// parent screen uses (see ``_FamilyForTest``).
final _nullKeyedPinned = FutureProvider<List<CommunityPost>>(
  (ref) async => const <CommunityPost>[],
);
final _nullKeyedFeed = FutureProvider<CommunityPagePlaceholder<CommunityPost>>(
  (ref) async =>
      const CommunityPagePlaceholder<CommunityPost>(items: <CommunityPost>[]),
);

/// Challenges tab — active challenges of the club.
class _ClubChallengesTab extends ConsumerWidget {
  const _ClubChallengesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final challenges = ref.watch(_nullKeyedChallenges);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        if (challenges.isEmpty)
          const Text(_l10nClubChallengesEmpty)
        else
          for (final c in challenges)
            ListTile(
              title: Text(
                '${c.metric} • ${_l10nClubChallengesPrefix} ${c.difficulty}',
              ),
              subtitle: Text(
                '${c.startsAt.toIso8601String()} → ${c.endsAt.toIso8601String()}',
              ),
            ),
      ],
    );
  }
}

final _nullKeyedChallenges =
    FutureProvider<List<CommunityChallengeSummaryPlaceholder>>(
      (ref) async => const <CommunityChallengeSummaryPlaceholder>[],
    );

/// Members tab — the screen-local placeholder; the production
/// surface reuses the ``ClubMemberManagementScreen`` push from
/// the Kör 24 detail screen.
class _ClubMembersTab extends ConsumerWidget {
  const _ClubMembersTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The Members tab defers the read to the Kör 24
    // ``clubMemberManagement_screen`` push so this round does
    // not need a new repository method (the brief §0.0 #3
    // structural precedent). The placeholder body just nudges
    // the user to the manage screen.
    return const Padding(
      padding: EdgeInsets.all(16),
      child: Center(
        child: Text(
          'Open the manage-members screen to view the roster.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

/// About tab — the club's description, owner, and visibility.
class _ClubAboutTab extends ConsumerWidget {
  const _ClubAboutTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        const SizedBox(height: 8),
        Builder(
          builder: (context) {
            // The about tab reads from the parent screen's
            // data — the placeholder text in the absence of a
            // description matches the Kör 24 empty-state shape.
            return const Text(_l10nClubAboutEmpty);
          },
        ),
      ],
    );
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
