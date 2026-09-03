/// Followers / following list screen (E09-R07, ADR 0401 §7).
///
/// One screen, two modes — "followers of X" vs "X follows" —
/// selected by the [FollowersMode] argument. The list is
/// cursor-paginated: the server returns an opaque ``next_cursor``
/// string, the screen requests the next page when the user
/// scrolls near the bottom, and the loop terminates when the
/// server returns a halted cursor (``null`` next_cursor after a
/// non-initial request — the §0.0 D3 Kör 3 distinction, l. 28).
///
/// The page envelope carries only public_ids (the
/// Kör 7 wire shape). The screen shows the public_id-derived
/// placeholder for now; the full ``CommunityProfile`` row arrives
/// through a future Kör 8 fetchById call that the controller will
/// chain in.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/public.dart';
import '../../../../core/foundation/app_failure.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/repositories/relationship_repository_impl.dart';
import '../../domain/entities/community_profile.dart';
import '../../domain/repositories/social_graph_repository.dart';
import '../../domain/value_objects/cursor_page.dart';
import '../../domain/value_objects/public_user_id.dart';
import '../widgets/community_theme_scope.dart';

enum FollowersMode { followers, following }

class FollowersScreen extends ConsumerStatefulWidget {
  const FollowersScreen({
    super.key,
    required this.profileId,
    required this.mode,
  });

  final PublicUserId profileId;
  final FollowersMode mode;

  @override
  ConsumerState<FollowersScreen> createState() => _FollowersScreenState();
}

class _FollowersScreenState extends ConsumerState<FollowersScreen> {
  final List<CommunityProfile> _items = <CommunityProfile>[];
  CursorPage _cursor = const CursorPage.initial();
  bool _isLoadingMore = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchInitial());
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> _fetchInitial() async {
    if (_disposed) return;
    final repo = ref.read(socialGraphRepositoryProvider);
    try {
      final page = widget.mode == FollowersMode.followers
          ? await repo.followersPage(userId: widget.profileId, cursor: _cursor)
          : await repo.followingPage(userId: widget.profileId, cursor: _cursor);
      if (_disposed) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page.items);
        _cursor = page.cursor;
      });
    } on AppFailure catch (failure) {
      if (_disposed) return;
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_formatFailure(failure))));
      }
    }
  }

  Future<void> _fetchNext() async {
    if (_isLoadingMore) return;
    if (_cursor.isInitial) return;
    if (_cursor.cursor == null) return; // halted
    if (_disposed) return;

    setState(() => _isLoadingMore = true);
    final repo = ref.read(socialGraphRepositoryProvider);
    try {
      final page = widget.mode == FollowersMode.followers
          ? await repo.followersPage(userId: widget.profileId, cursor: _cursor)
          : await repo.followingPage(userId: widget.profileId, cursor: _cursor);
      if (_disposed) return;
      setState(() {
        _items.addAll(page.items);
        _cursor = page.cursor;
      });
    } on AppFailure catch (failure) {
      if (_disposed) return;
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_formatFailure(failure))));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  String _formatFailure(AppFailure failure) {
    if (failure is NetworkFailure) {
      return 'Network error';
    }
    return 'Server error';
  }

  /// A5 — the row disappears from THIS list immediately, before the
  /// repository call is even awaited; the server round-trip is best-effort
  /// and never re-adds the row (ADR 0291 §4, "the tiltás hat helyben azonnal,
  /// nem kell megvárni a szerver megerősítését").
  Future<void> _blockUser(PublicUserId target) => _applyLocallyThen(
    target,
    (repo, key) => repo.block(target: target, idempotencyKey: key),
  );

  Future<void> _muteUser(PublicUserId target) => _applyLocallyThen(
    target,
    (repo, key) => repo.mute(target: target, idempotencyKey: key),
  );

  Future<void> _applyLocallyThen(
    PublicUserId target,
    Future<void> Function(SocialGraphRepository repo, String idempotencyKey)
    call,
  ) async {
    setState(() => _items.removeWhere((p) => p.userId == target));
    final repo = ref.read(socialGraphRepositoryProvider);
    try {
      await call(repo, _newRelationshipActionKey());
    } on AppFailure catch (_) {
      // Best-effort — the local view already reflects the safety
      // decision regardless of the server round-trip outcome.
    }
  }

  String _newRelationshipActionKey() =>
      'fw-${DateTime.now().microsecondsSinceEpoch}';

  @override
  Widget build(BuildContext context) {
    final title = widget.mode == FollowersMode.followers
        ? 'Followers'
        : 'Following';
    return CommunityThemeScope(
      child: Scaffold(
        appBar: AppBar(title: Text(title)),
        body: SafeArea(
          child: _items.isEmpty
              ? Builder(
                  builder: (context) {
                    final colors = Theme.of(
                      context,
                    ).extension<SsColorScheme>()!;
                    final typography = Theme.of(
                      context,
                    ).extension<SsTypography>()!;
                    return Center(
                      child: Text(
                        'No one here yet.',
                        style: typography.bodyMedium.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    );
                  },
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(SsSpacing.space4),
                  itemCount: _items.length + 1,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: SsSpacing.space2),
                  itemBuilder: (context, index) {
                    if (index >= _items.length) {
                      // Tail load: kick off the next page when the
                      // user scrolls near the bottom. The cursor's
                      // null means the server is done.
                      if (!_cursor.isInitial && _cursor.cursor != null) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!_disposed) _fetchNext();
                        });
                      }
                      return _Footer(isLoading: _isLoadingMore);
                    }
                    final profile = _items[index];
                    return _FollowerTile(
                      profile: profile,
                      onBlock: () => _blockUser(profile.userId),
                      onMute: () => _muteUser(profile.userId),
                    );
                  },
                ),
        ),
      ),
    );
  }
}

class _FollowerTile extends StatelessWidget {
  const _FollowerTile({
    required this.profile,
    required this.onBlock,
    required this.onMute,
  });

  final CommunityProfile profile;
  final VoidCallback onBlock;
  final VoidCallback onMute;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
    return SsCard(
      child: Row(
        children: [
          // MINOR-3 (E15-R11 review): the avatar's own fill (surfaceRaised)
          // barely differs from the SsCard's raised background it now sits
          // on (light 1.01:1, dark 1.09:1, measured off the recorded
          // golden). `borderStrong` gives it a measurable edge (17.25:1
          // light / 13.04:1 dark, tool/ui_contrast_check.dart) instead of a
          // new token.
          DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: colors.borderStrong, width: 1.5),
            ),
            child: CircleAvatar(
              radius: 24,
              backgroundColor: colors.surfaceRaised,
              child: Text(
                profile.displayName.isEmpty
                    ? profile.handle.value.isEmpty
                          ? '?'
                          : profile.handle.value[0].toUpperCase()
                    : profile.displayName[0].toUpperCase(),
                style: typography.bodyLarge.copyWith(color: colors.textPrimary),
              ),
            ),
          ),
          const SizedBox(width: SsSpacing.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.displayName.isEmpty
                      ? profile.userId.value
                      : profile.displayName,
                  style: typography.titleMedium.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
                if (profile.handle.value.isNotEmpty)
                  Text(
                    '@${profile.handle.value}',
                    style: typography.bodyMedium.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            key: ValueKey('follower-mute-${profile.userId.value}'),
            tooltip: l10n.communityFollowersMuteAction,
            icon: Icon(Icons.volume_off_outlined, color: colors.textSecondary),
            onPressed: onMute,
          ),
          IconButton(
            key: ValueKey('follower-block-${profile.userId.value}'),
            tooltip: l10n.communityFollowersBlockAction,
            icon: Icon(Icons.block_outlined, color: colors.danger),
            onPressed: onBlock,
          ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.isLoading});

  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SsSpacing.space4),
      child: Center(
        // MAJOR-2 (E15-R11 review): the footer betöltés-állapot a
        // design-rendszer betöltés-komponensére vált (§5.2) — raw
        // CircularProgressIndicator was a documented not-acceptable
        // weakening.
        child: isLoading
            ? const SsSkeleton(
                key: Key('followers-footer-loading'),
                width: 18,
                height: 18,
                radius: 9,
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}
