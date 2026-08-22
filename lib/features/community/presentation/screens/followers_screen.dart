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

import '../../../../core/foundation/app_failure.dart';
import '../../data/repositories/relationship_repository_impl.dart';
import '../../domain/entities/community_profile.dart';
import '../../domain/value_objects/cursor_page.dart';
import '../../domain/value_objects/public_user_id.dart';

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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_formatFailure(failure))),
        );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_formatFailure(failure))),
        );
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

  @override
  Widget build(BuildContext context) {
    final title = widget.mode == FollowersMode.followers
        ? 'Followers'
        : 'Following';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: _items.isEmpty
            ? const Center(child: Text('No one here yet.'))
              : ListView.separated(
                  itemCount: _items.length + 1,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
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
                    return _FollowerTile(profile: profile);
                  },
                ),
      ),
    );
  }
}

class _FollowerTile extends StatelessWidget {
  const _FollowerTile({required this.profile});

  final CommunityProfile profile;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
            child: Text(
              profile.displayName.isEmpty
                  ? profile.handle.value.isEmpty
                        ? '?'
                        : profile.handle.value[0].toUpperCase()
                  : profile.displayName[0].toUpperCase(),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.displayName.isEmpty
                      ? profile.userId.value
                      : profile.displayName,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                if (profile.handle.value.isNotEmpty)
                  Text(
                    '@${profile.handle.value}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
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
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: isLoading
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}