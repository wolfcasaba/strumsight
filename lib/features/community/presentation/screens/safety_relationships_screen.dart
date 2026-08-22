/// Blocked / Muted users settings screen (E09-R08, ADR 0402).
///
/// SDD UI-61 calls for a "Blocked users / Muted threads" settings
/// surface. The screen exposes two tabs — Blocked and Muted — each
/// rendering the caller's own list. The lists are loaded via the
/// new ``blockedProfilesPage`` / ``mutedProfilesPage`` repository
/// methods (ADR 0402 §D5) and the underlying follow-list wire
/// envelope (``public_ids`` + ``next_cursor``).
///
/// Per ADR 0402 §D6 the screen owns its own Riverpod state — the
/// pre-existing ``relationship_controller.dart`` does not know
/// about block / mute operations and the
/// ``application/controllers/**`` tree is OUT of scope for this
/// round. The notifier below is defined at the top of this file
/// (not in a separate ``application/controllers/`` file) so the
/// screen is a single, self-contained file.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/foundation/app_failure.dart';
import '../../data/repositories/profile_repository_impl.dart';
import '../../data/repositories/relationship_repository_impl.dart';
import '../../domain/entities/community_profile.dart';
import '../../domain/repositories/community_profile_repository.dart';
import '../../domain/value_objects/cursor_page.dart';
import '../../domain/value_objects/public_user_id.dart';

/// Which list the screen is showing. Two-tab surface — Blocked on
/// the left, Muted on the right (or stacked on a small phone).
enum SafetyTab { blocked, muted }

/// Per-tab Riverpod state. Lives here (not in ``application/controllers/``)
/// per ADR 0402 §D6 — the screen is the single file that owns this
/// state, including the cursor pagination, the resolved-profile
/// cache, and the per-action unblock / unmute call sites.
final _safetyListProvider = StateNotifierProvider.family
    .autoDispose<_SafetyListNotifier, _SafetyListState, SafetyTab>(
      (ref, tab) => _SafetyListNotifier(ref: ref, tab: tab),
    );

class _SafetyListState {
  const _SafetyListState({
    required this.items,
    required this.cursor,
    required this.isLoading,
    this.failureMessage,
  });

  final List<CommunityProfile> items;
  final CursorPage cursor;
  final bool isLoading;
  final String? failureMessage;

  _SafetyListState copyWith({
    List<CommunityProfile>? items,
    CursorPage? cursor,
    bool? isLoading,
    String? failureMessage,
  }) {
    return _SafetyListState(
      items: items ?? this.items,
      cursor: cursor ?? this.cursor,
      isLoading: isLoading ?? this.isLoading,
      failureMessage: failureMessage,
    );
  }
}

class _SafetyListNotifier extends StateNotifier<_SafetyListState> {
  _SafetyListNotifier({required Ref ref, required this.tab})
    : _ref = ref,
      super(
        const _SafetyListState(
          items: <CommunityProfile>[],
          cursor: CursorPage.initial(),
          isLoading: false,
        ),
      );

  final Ref _ref;
  final SafetyTab tab;

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> loadInitial() async {
    if (_disposed) return;
    state = state.copyWith(isLoading: true, failureMessage: null);
    try {
      final page = await _fetch(cursor: const CursorPage.initial());
      if (_disposed) return;
      state = state.copyWith(
        items: page.items,
        cursor: page.cursor,
        isLoading: false,
      );
    } on AppFailure catch (failure) {
      if (_disposed) return;
      state = state.copyWith(
        isLoading: false,
        failureMessage: _formatFailure(failure),
      );
    }
  }

  Future<void> loadNext() async {
    if (state.isLoading) return;
    if (state.cursor.isInitial) return;
    if (state.cursor.cursor == null) return; // halted
    if (_disposed) return;
    state = state.copyWith(isLoading: true, failureMessage: null);
    try {
      final page = await _fetch(cursor: state.cursor);
      if (_disposed) return;
      state = state.copyWith(
        items: <CommunityProfile>[...state.items, ...page.items],
        cursor: page.cursor,
        isLoading: false,
      );
    } on AppFailure catch (failure) {
      if (_disposed) return;
      state = state.copyWith(
        isLoading: false,
        failureMessage: _formatFailure(failure),
      );
    }
  }

  Future<void> unblock(PublicUserId target) async {
    final repo = _ref.read(socialGraphRepositoryProvider);
    try {
      await repo.unblock(target: target, idempotencyKey: _newKey());
    } on AppFailure {
      rethrow;
    }
    // Optimistic local removal — the next page-load will reconcile.
    if (_disposed) return;
    state = state.copyWith(
      items: state.items
          .where((profile) => profile.userId != target)
          .toList(growable: false),
    );
  }

  Future<void> unmute(PublicUserId target) async {
    final repo = _ref.read(socialGraphRepositoryProvider);
    try {
      await repo.unmute(target: target, idempotencyKey: _newKey());
    } on AppFailure {
      rethrow;
    }
    if (_disposed) return;
    state = state.copyWith(
      items: state.items
          .where((profile) => profile.userId != target)
          .toList(growable: false),
    );
  }

  Future<List<CommunityProfile>> _fetchResolved(CursorPage cursor) async {
    final page = await _fetch(cursor: cursor);
    final profileRepo = _ref.read(communityProfileRepositoryProvider);
    final resolved = <CommunityProfile>[];
    for (final placeholder in page.items) {
      try {
        final full = await profileRepo.fetchById(placeholder.userId);
        resolved.add(full);
      } on AppFailure {
        // Fall back to the placeholder — the screen still renders.
        resolved.add(placeholder);
      }
    }
    return resolved;
  }

  Future<CommunityPage<CommunityProfile>> _fetch({required CursorPage cursor}) async {
    final repo = _ref.read(socialGraphRepositoryProvider);
    return switch (tab) {
      SafetyTab.blocked => repo.blockedProfilesPage(cursor: cursor),
      SafetyTab.muted => repo.mutedProfilesPage(cursor: cursor),
    };
  }

  String _newKey() {
    // A bare-bones local UUID-ish generator. The repository layer
    // only requires a non-empty string for the idempotency key;
    // a future round can swap this for a real UUID generator if
    // the backend demands more.
    return 'sr-${DateTime.now().microsecondsSinceEpoch}';
  }
}

String _formatFailure(AppFailure failure) {
  switch (failure.code) {
    case FailureCode.networkUnavailable:
      return 'No network connection';
    case FailureCode.authSessionExpired:
      return 'Session expired — please sign in again';
    case FailureCode.authForbidden:
      return 'You do not have permission to view this list';
    case FailureCode.validationInvalidInput:
      return 'Invalid request';
    default:
      // The FailureCode contract is the only thing that crosses
      // into the presentation layer — there is no English message
      // to echo. The fallback is the code itself so a future
      // localiser can map it.
      return failure.toString();
  }
}

/// Public screen — ``ConsumerWidget`` so the test surface is the
/// ``ProviderScope`` override of the repository.
class SafetyRelationshipsScreen extends ConsumerWidget {
  const SafetyRelationshipsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: SafetyTab.values.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Blocked & muted'),
          bottom: const TabBar(
            tabs: <Widget>[
              Tab(text: 'Blocked'),
              Tab(text: 'Muted'),
            ],
          ),
        ),
        body: const TabBarView(
          children: <Widget>[
            _SafetyTabBody(tab: SafetyTab.blocked),
            _SafetyTabBody(tab: SafetyTab.muted),
          ],
        ),
      ),
    );
  }
}

class _SafetyTabBody extends ConsumerStatefulWidget {
  const _SafetyTabBody({required this.tab});

  final SafetyTab tab;

  @override
  ConsumerState<_SafetyTabBody> createState() => _SafetyTabBodyState();
}

class _SafetyTabBodyState extends ConsumerState<_SafetyTabBody> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(_safetyListProvider(widget.tab).notifier).loadInitial();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(_safetyListProvider(widget.tab));
    final notifier = ref.read(_safetyListProvider(widget.tab).notifier);

    if (state.isLoading && state.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.failureMessage != null && state.items.isEmpty) {
      return Center(child: Text(state.failureMessage!));
    }
    if (state.items.isEmpty) {
      return Center(
        child: Text(
          widget.tab == SafetyTab.blocked
              ? 'You haven\'t blocked anyone yet.'
              : 'You haven\'t muted anyone yet.',
        ),
      );
    }

    final halted = state.cursor.isInitial || state.cursor.cursor == null;
    return ListView.separated(
      itemCount: state.items.length + (halted ? 0 : 1),
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        if (index >= state.items.length) {
          // Footer — triggers the next page fetch.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            notifier.loadNext();
          });
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final profile = state.items[index];
        return ListTile(
          title: Text(profile.displayName.isEmpty
              ? profile.userId.value
              : profile.displayName),
          subtitle: Text(profile.handle.value),
          trailing: TextButton(
            onPressed: () async {
              try {
                if (widget.tab == SafetyTab.blocked) {
                  await notifier.unblock(profile.userId);
                } else {
                  await notifier.unmute(profile.userId);
                }
              } on AppFailure catch (failure) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(_formatFailure(failure))),
                );
              }
            },
            child: Text(widget.tab == SafetyTab.blocked ? 'Unblock' : 'Unmute'),
          ),
        );
      },
    );
  }
}
