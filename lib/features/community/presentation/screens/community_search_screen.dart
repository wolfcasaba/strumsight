/// Community profile search screen (E09-R09, brief §3 / §A5).
///
/// The screen wraps a debounced text input, a recent-searches
/// surface, and a result list backed by the Kör 9 endpoint
/// (``GET /community/profiles/search``). The screen itself owns
/// no business state — every fetch goes through the existing
/// ``communityProfileRepositoryProvider`` so a feature-flag or a
/// future controller wiring stays a single-line change.
///
/// **Privacy (A5):** the recent-searches list is read from and
/// written to the local ``RecentSearchStore`` only — no
/// SharedPreferences flush, no analytics ping, no server
/// upload. The store exposes ``remove`` and ``clear`` so the
/// user can wipe the list at any moment.
///
/// **Debounce:** the implementation posts the search request
/// 300 ms after the last keystroke. The backend
/// ``MIN_QUERY_LENGTH`` gate (3 chars) is server-enforced, but
/// the screen itself skips the round-trip until the user typed
/// at least one character — fewer network slots consumed on
/// the rapid typing that the §9 DoS surface identifies.
///
/// **Result → profile navigation:** the brief does not pin a
/// destination route for a tapped result; the canonical
/// ``CommunityProfile`` view is the Kör 5 fetchById surface,
/// not in scope for E09-R09. The screen taps the user-visible
/// "View profile" affordance but does not invoke it yet — the
/// navigation hook is wired behind a no-op callback so a future
/// Kör 10+ can drop the route in without re-touching this
/// file.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/foundation/app_failure.dart';
import '../../../../core/storage/key_value_store.dart';
import '../../data/local/recent_search_store.dart';
import '../../data/repositories/profile_repository_impl.dart';
import '../../domain/entities/community_profile.dart';
import '../../domain/repositories/community_page.dart';
import '../../domain/value_objects/cursor_page.dart';
import '../../domain/value_objects/public_user_id.dart';

/// Debounce window for the typed query — long enough to swallow
/// burst typing, short enough that the user sees results within
/// a single sentence. The exact value is a UX choice; the
/// backend's ``MIN_QUERY_LENGTH`` is the safety net for the
/// shorter-window DoS surface.
const Duration _searchDebounce = Duration(milliseconds: 300);

/// Max results rendered on the screen before the user scrolls
/// past. The server still returns up to ``limit=50`` per page;
/// 50 is a reasonable UX cap for a small mobile viewport.
const int _maxVisibleResults = 50;

class CommunitySearchScreen extends ConsumerStatefulWidget {
  const CommunitySearchScreen({super.key, this.recentSearchStore});

  /// Optional injected store for tests. Production wires the
  /// SharedPreferences-backed implementation through the app
  /// boot path; tests can pass an in-memory fake.
  final RecentSearchStore? recentSearchStore;

  @override
  ConsumerState<CommunitySearchScreen> createState() =>
      _CommunitySearchScreenState();
}

class _CommunitySearchScreenState extends ConsumerState<CommunitySearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  Timer? _debounceTimer;

  /// Last query actually sent to the backend. Distinct from the
  /// controller text — the debounce window may leave a typed
  /// but-not-yet-sent query sitting in the controller.
  String _activeQuery = '';

  /// Last search response — items + cursor. The list is the
  /// raw slice the backend returned; the recent-search list
  /// has its own in-memory model.
  CommunityPage<CommunityProfile>? _lastPage;

  /// Loading + error flags for the in-flight search.
  bool _isLoading = false;
  AppFailure? _error;

  /// Recent searches — refreshed on initState / clear / push /
  /// remove. The store is the source of truth; this field is a
  /// cached snapshot for the build method.
  List<String> _recent = const <String>[];

  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _recent = widget.recentSearchStore?.read() ?? const <String>[];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _debounceTimer?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  RecentSearchStore? get _store => widget.recentSearchStore;

  void _onQueryChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_searchDebounce, () {
      if (_disposed) return;
      _runSearch(value.trim());
    });
  }

  Future<void> _runSearch(String trimmed) async {
    if (_disposed) return;
    if (trimmed.isEmpty) {
      setState(() {
        _activeQuery = '';
        _lastPage = null;
        _error = null;
      });
      return;
    }
    if (trimmed == _activeQuery) return; // idempotent: nothing changed
    setState(() {
      _isLoading = true;
      _error = null;
      _activeQuery = trimmed;
    });
    final repo = ref.read(communityProfileRepositoryProvider);
    try {
      final page = await repo.searchProfiles(
        query: trimmed,
        cursor: const CursorPage.initial(),
      );
      if (_disposed) return;
      setState(() {
        _lastPage = page;
        _isLoading = false;
      });
    } on AppFailure catch (failure) {
      if (_disposed) return;
      setState(() {
        _lastPage = null;
        _isLoading = false;
        _error = failure;
      });
    }
  }

  Future<void> _onSubmit(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    // A submit (keyboard "search" key) bypasses the debounce so
    // the user can lock in a query without waiting.
    _debounceTimer?.cancel();
    final store = _store;
    if (store != null) {
      try {
        await store.push(trimmed);
        if (_disposed) return;
        setState(() {
          _recent = store.read();
        });
      } on StorageException {
        // The user-visible invariant is "the search works even
        // when recent-history storage fails". Swallow the error
        // (the search itself is unaffected); the store will
        // surface a snackbar through the controller layer in a
        // future round (no controller on this screen yet).
      }
    }
    await _runSearch(trimmed);
  }

  Future<void> _onTapRecent(String query) async {
    _controller.text = query;
    _controller.selection = TextSelection.collapsed(offset: query.length);
    await _onSubmit(query);
  }

  Future<void> _removeRecent(String query) async {
    final store = _store;
    if (store == null) return;
    try {
      await store.remove(query);
      if (_disposed) return;
      setState(() {
        _recent = store.read();
      });
    } on StorageException catch (exception) {
      _showSnack(
        _storageFailureMessage(mapRecentSearchStorageException(exception)),
      );
    }
  }

  Future<void> _clearRecent() async {
    final store = _store;
    if (store == null) return;
    try {
      await store.clear();
      if (_disposed) return;
      setState(() {
        _recent = const <String>[];
      });
    } on StorageException catch (exception) {
      _showSnack(
        _storageFailureMessage(mapRecentSearchStorageException(exception)),
      );
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _storageFailureMessage(AppFailure failure) {
    return 'Could not update recent searches';
  }

  String _formatFailure(AppFailure failure) {
    if (failure is NetworkFailure) return 'Network error';
    return 'Server error';
  }

  @override
  Widget build(BuildContext context) {
    final hasQuery = _activeQuery.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          focusNode: _focusNode,
          autocorrect: false,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Search by handle',
            border: InputBorder.none,
          ),
          onChanged: _onQueryChanged,
          onSubmitted: _onSubmit,
        ),
        actions: [
          if (_controller.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              tooltip: 'Clear',
              onPressed: () {
                _controller.clear();
                _onQueryChanged('');
              },
            ),
        ],
      ),
      body: SafeArea(child: _buildBody(hasQuery)),
    );
  }

  Widget _buildBody(bool hasQuery) {
    if (!hasQuery) {
      return _RecentList(
        recent: _recent,
        onTap: _onTapRecent,
        onRemove: _removeRecent,
        onClear: _clearRecent,
      );
    }
    if (_isLoading && _lastPage == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _ErrorState(
        message: _formatFailure(_error!),
        onRetry: () => _runSearch(_activeQuery),
      );
    }
    final items = _lastPage?.items ?? const <CommunityProfile>[];
    final visible = items.length > _maxVisibleResults
        ? items.sublist(0, _maxVisibleResults)
        : items;
    return _ResultsList(items: visible);
  }
}

class _RecentList extends StatelessWidget {
  const _RecentList({
    required this.recent,
    required this.onTap,
    required this.onRemove,
    required this.onClear,
  });

  final List<String> recent;
  final Future<void> Function(String) onTap;
  final Future<void> Function(String) onRemove;
  final Future<void> Function() onClear;

  @override
  Widget build(BuildContext context) {
    if (recent.isEmpty) {
      return const _EmptyState(
        icon: Icons.search,
        message: 'Type a handle prefix to discover players.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Recent searches',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              TextButton(onPressed: onClear, child: const Text('Clear all')),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: recent.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final query = recent[index];
              return ListTile(
                leading: const Icon(Icons.history),
                title: Text(query),
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Remove',
                  onPressed: () => onRemove(query),
                ),
                onTap: () => onTap(query),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ResultsList extends StatelessWidget {
  const _ResultsList({required this.items});

  final List<CommunityProfile> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const _EmptyState(
        icon: Icons.person_search,
        message: 'No matches.',
      );
    }
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final profile = items[index];
        return ListTile(
          leading: CircleAvatar(
            child: Text(
              profile.displayName.isEmpty
                  ? '?'
                  : profile.displayName[0].toUpperCase(),
            ),
          ),
          title: Text(profile.displayName),
          subtitle: profile.handle.value.isNotEmpty
              ? Text('@${profile.handle.value}')
              : null,
          onTap: () {
            // Brief §A2 — taps open the canonical profile view
            // (Kör 5 fetchById surface). The route is wired by
            // a future Kör 10 round; this onTap is a no-op
            // marker so the navigation hook is obvious in code
            // review.
            unawaited(_noopOnTap(profile.userId));
          },
        );
      },
    );
  }
}

Future<void> _noopOnTap(PublicUserId userId) async {
  // Anchor for the Kör 10 navigation hook. Intentionally empty:
  // the canonical profile view is not in scope for E09-R09.
  HapticFeedback.selectionClick();
  // The unused parameter keeps the signature obvious in grep
  // for the future round.
  assert(userId.value.isNotEmpty);
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 40),
          const SizedBox(height: 8),
          Text(message),
          const SizedBox(height: 8),
          ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40),
          const SizedBox(height: 8),
          Text(message),
        ],
      ),
    );
  }
}
