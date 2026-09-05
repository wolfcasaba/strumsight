/// Blocked / Muted users settings screen (E09-R08, ADR 0402;
/// design-system migration E13-R34).
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

import 'package:strumsight/core/design_system/public.dart';

import '../../../../core/foundation/app_failure.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/repositories/relationship_repository_impl.dart';
import '../../domain/entities/community_profile.dart';
import '../../domain/repositories/community_page.dart';
import '../../domain/value_objects/cursor_page.dart';
import '../../domain/value_objects/public_user_id.dart';
import '../widgets/community_theme_scope.dart';

/// Which list the screen is showing. Two-tab surface — Blocked on
/// the left, Muted on the right (or stacked on a small phone).
enum SafetyTab { blocked, muted }

/// Per-tab Riverpod state. Lives here (not in ``application/controllers/``)
/// per ADR 0402 §D6 — the screen is the single file that owns this
/// state, including the cursor pagination, the resolved-profile
/// cache, and the per-action unblock / unmute call sites.
///
/// Riverpod 3.3.2 removed ``FamilyNotifier`` (CHANGELOG: 114); the
/// pattern is ``extends Notifier<StateT>`` + a constructor that
/// captures the family arg as a field. The
/// ``NotifierProvider.family<...>(Notifier.new)`` calls the
/// constructor for each family entry.
final safetyListProvider =
    NotifierProvider.family<_SafetyListNotifier, _SafetyListState, SafetyTab>(
      _SafetyListNotifier.new,
    );

class _SafetyListState {
  const _SafetyListState({
    required this.items,
    required this.cursor,
    required this.isLoading,
    this.failure,
  });

  final List<CommunityProfile> items;
  final CursorPage cursor;
  final bool isLoading;
  final AppFailure? failure;

  _SafetyListState copyWith({
    List<CommunityProfile>? items,
    CursorPage? cursor,
    bool? isLoading,
    AppFailure? failure,
    bool clearFailure = false,
  }) {
    return _SafetyListState(
      items: items ?? this.items,
      cursor: cursor ?? this.cursor,
      isLoading: isLoading ?? this.isLoading,
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }
}

class _SafetyListNotifier extends Notifier<_SafetyListState> {
  _SafetyListNotifier(this.tab);

  /// The family arg — which tab this notifier instance manages.
  final SafetyTab tab;

  bool _disposed = false;

  @override
  _SafetyListState build() {
    ref.onDispose(() {
      _disposed = true;
    });
    return const _SafetyListState(
      items: <CommunityProfile>[],
      cursor: CursorPage.initial(),
      isLoading: false,
    );
  }

  Future<void> loadInitial() async {
    if (_disposed) return;
    state = state.copyWith(isLoading: true, clearFailure: true);
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
      state = state.copyWith(isLoading: false, failure: failure);
    }
  }

  Future<void> loadNext() async {
    if (state.isLoading) return;
    if (state.cursor.isInitial) return;
    if (state.cursor.cursor == null) return; // halted
    if (_disposed) return;
    state = state.copyWith(isLoading: true, clearFailure: true);
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
      state = state.copyWith(isLoading: false, failure: failure);
    }
  }

  Future<void> unblock(PublicUserId target) async {
    final repo = ref.read(socialGraphRepositoryProvider);
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
    final repo = ref.read(socialGraphRepositoryProvider);
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

  Future<CommunityPage<CommunityProfile>> _fetch({
    required CursorPage cursor,
  }) async {
    final repo = ref.read(socialGraphRepositoryProvider);
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

String _formatFailure(BuildContext context, AppFailure failure) {
  final localizations = AppLocalizations.of(context);
  switch (failure.code) {
    case FailureCode.networkUnavailable:
      return localizations.safetyErrorNetwork;
    case FailureCode.authSessionExpired:
      return localizations.safetyErrorSessionExpired;
    case FailureCode.authForbidden:
      return localizations.safetyErrorForbidden;
    case FailureCode.validationInvalidInput:
      return localizations.safetyErrorInvalidInput;
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
    final localizations = AppLocalizations.of(context);
    return CommunityThemeScope(
      child: DefaultTabController(
        length: SafetyTab.values.length,
        child: Scaffold(
          appBar: AppBar(
            title: Text(localizations.safetyBlockedMutedTitle),
            // A fül-sáv magassága a SZÖVEG-MÉRETTEL nő (2026-09-05).
            // A `TabBar` alapértelmezett magassága fix; 2.0-s szöveg-
            // méretnél a fül felirata túlcsordult, azaz pont azoknak
            // vágódott le, akik a nagy betűt bekapcsolták. A
            // `PreferredSize` a mért méretezővel skálázza a magasságot.
            bottom: PreferredSize(
              preferredSize: Size.fromHeight(
                MediaQuery.textScalerOf(context).scale(kTextTabBarHeight),
              ),
              child: TabBar(
                tabs: <Widget>[
                  Tab(text: localizations.safetyBlockedTab),
                  Tab(text: localizations.safetyMutedTab),
                ],
              ),
            ),
          ),
          body: const TabBarView(
            children: <Widget>[
              _SafetyTabBody(tab: SafetyTab.blocked),
              _SafetyTabBody(tab: SafetyTab.muted),
            ],
          ),
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
      ref.read(safetyListProvider(widget.tab).notifier).loadInitial();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(safetyListProvider(widget.tab));
    final notifier = ref.read(safetyListProvider(widget.tab).notifier);
    final localizations = AppLocalizations.of(context);

    if (state.isLoading && state.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.failure != null && state.items.isEmpty) {
      return Center(child: Text(_formatFailure(context, state.failure!)));
    }
    if (state.items.isEmpty) {
      return Center(
        child: Text(
          widget.tab == SafetyTab.blocked
              ? localizations.safetyEmptyBlocked
              : localizations.safetyEmptyMuted,
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
          title: Text(
            profile.displayName.isEmpty
                ? profile.userId.value
                : profile.displayName,
          ),
          // A művelet-gomb a felirat ALÁ kerül, nem mellé (2026-09-05).
          // A `trailing` pozícióban 2.0-s szöveg-méretnél a gomb az EGÉSZ
          // sor szélességét elvette (a Flutter saját hibaüzenete mondta
          // ki), és a név eltűnt mögüle. Alatta minden szöveg-méreten
          // elfér, és a gomb továbbra is egy koppintásra van.
          isThreeLine: true,
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(profile.handle.value),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: SsButton(
                  variant: SsButtonVariant.secondary,
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
                        SnackBar(
                          content: Text(_formatFailure(context, failure)),
                        ),
                      );
                    }
                  },
                  label: widget.tab == SafetyTab.blocked
                      ? localizations.safetyUnblock
                      : localizations.safetyUnmute,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
