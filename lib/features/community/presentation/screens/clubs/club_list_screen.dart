/// Club list screen (E09-R24, ADR 0420, brief §3).
///
/// Renders the caller's visible-clubs list (private clubs for
/// members, discoverable / public for anyone) and embeds the
/// create-club UI as a dialog / sheet (per ADR 0420 D7 — no
/// standalone create-screen file is on the allowed_paths list).
///
/// **Why a single screen (D7).** The brief §3 "create screen"
/// wording is imprecise — the §4 allowed_paths list has only
/// three screen files, and the §0.0 / D7 decision consolidates
/// the create flow into the list screen so this round ships
/// without a fourth file.
///
/// **Repository surface.** The screen reads the
/// ``communityClubRepositoryProvider`` (Kör 24 only wires the
/// provider + interface — the http-backed implementation is a
/// future round). The test surface is the
/// ``ProviderScope`` override (the Kör 23 / Kör 21 pattern).
///
/// **Visibility filter.** The list filter applies the
/// visibility rule from the backend: private clubs surface only
/// for members; discoverable / public clubs surface for anyone
/// — but blocked owners' clubs are filtered out by the
/// backend's block-side gate.
///
/// **Accessibility (A7).** The list rows expose a single
/// ``Semantics`` node per club with the club name + visibility
/// + member count so a screen-reader reads each row in one
/// utterance. Text widgets go through
/// ``MediaQuery.textScalerOf(context).scale(...)`` so a 2× text
/// setting keeps the row readable.
///
/// **Localization note (l10n).** The labels are hardcoded
/// English placeholders — the ARB file is not on this round's
/// ``allowed_paths``. The strings live at the top of the file
/// so a future ARB migration is a search-and-replace.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/foundation/app_failure.dart';
import '../../../domain/entities/community_club.dart';
import '../../../domain/repositories/club_repository.dart';
import '../../../domain/repositories/community_page.dart';
import '../../../domain/value_objects/cursor_page.dart';

// ---------------------------------------------------------------------------
// L10n placeholders — to be lifted into app_en.arb / app_hu.arb in a
// future round (the Kör 18 community-surface l10n lift).
// ---------------------------------------------------------------------------

const String _l10nClubListTitle = 'Clubs';
const String _l10nClubListEmpty = 'No clubs yet. Create one to get started.';
const String _l10nClubListError = "The clubs couldn't load.";
const String _l10nClubListRetry = 'Retry';
const String _l10nClubListCreate = 'Create club';
const String _l10nClubListCreateName = 'Club name';
const String _l10nClubListCreateDescription = 'Description';
const String _l10nClubListCreateVisibility = 'Visibility';
const String _l10nClubListCreateSubmit = 'Create';
const String _l10nClubListCreateCancel = 'Cancel';
const String _l10nClubListLoadMore = 'Load more';
const String _l10nClubVisibilityPrivate = 'Private';
const String _l10nClubVisibilityDiscoverable = 'Discoverable';
const String _l10nClubVisibilityPublic = 'Public';

/// First-page size — matches the Kör 23 / Kör 21 list pagination
/// shape. The future wire implementation can re-tune against
/// the cursor-stability invariants.
const int _kClubListPageSize = 25;

/// Repository provider stub — the Kör 24 wire-backed
/// implementation is a future round (``data/repositories/
/// club_repository_impl.dart`` is NOT on this round's
/// ``allowed_paths``). The provider is the override seam:
/// widget tests inject a recording fake via ``ProviderScope``,
/// production code will inject the http impl once it lands.
final communityClubRepositoryProvider = Provider<CommunityClubRepository>(
  (ref) => throw UnimplementedError(
    'communityClubRepositoryProvider: Kör 24 wire impl not in scope; '
    'override via ProviderScope in tests.',
  ),
);

/// FutureProvider for the first page of the visible-clubs list.
/// ``autoDispose`` so the screen is cheap to enter / leave;
/// ``family`` so multiple screens / navigations stay independent.
final clubListProvider = FutureProvider.autoDispose
    .family<CommunityPage<CommunityClub>, Object>((ref, cursor) async {
      final repo = ref.watch(communityClubRepositoryProvider);
      final page = await repo.listClubs(
        cursor: cursor,
        limit: _kClubListPageSize,
      );
      return page;
    });

/// Public screen — ``ConsumerWidget`` so the test surface is the
/// ``ProviderScope`` override of the
/// ``communityClubRepositoryProvider`` (the Kör 23 / Kör 21
/// pattern).
class ClubListScreen extends ConsumerWidget {
  const ClubListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(clubListProvider(const CursorPage.initial()));

    return Scaffold(
      appBar: AppBar(
        title: const Text(_l10nClubListTitle),
        actions: <Widget>[
          IconButton(
            tooltip: _l10nClubListCreate,
            icon: const Icon(Icons.add),
            onPressed: () => _showCreateClubDialog(context, ref),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(clubListProvider(const CursorPage.initial()));
          await ref.read(clubListProvider(const CursorPage.initial()).future);
        },
        child: state.when(
          data: (page) => _Body(
            page: page,
            onLoadMore: () async {
              ref.invalidate(clubListProvider(const CursorPage.initial()));
              await ref.read(
                clubListProvider(const CursorPage.initial()).future,
              );
            },
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _ErrorView(
            failure: UnknownFailure(code: FailureCode.unknown, cause: error),
            onRetry: () async {
              ref.invalidate(clubListProvider(const CursorPage.initial()));
              await ref.read(
                clubListProvider(const CursorPage.initial()).future,
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _showCreateClubDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    // The Kör 24 create flow lives inside the list screen per
    // ADR 0420 D7. The dialog is intentionally minimal — the
    // future wire implementation reads the
    // ``createClub(...)`` repository call. The test surface
    // for this flow is a Kör 25 surface (the Kör 24
    // allowed_paths includes the screen file only, not a
    // dedicated widget test for the dialog).
    final repo = ref.read(communityClubRepositoryProvider);
    await showDialog<void>(
      context: context,
      builder: (ctx) => _CreateClubDialog(
        onCreate:
            ({
              required String name,
              required String description,
              required ClubVisibility visibility,
              required List<String> tags,
              required String idempotencyKey,
            }) async {
              await repo.createClub(
                name: name,
                description: description,
                visibility: visibility,
                tags: tags,
                idempotencyKey: idempotencyKey,
              );
            },
      ),
    );
    if (context.mounted) {
      ref.invalidate(clubListProvider(const CursorPage.initial()));
    }
  }
}

// ---------------------------------------------------------------------------
// Body — empty / list / load-more row.
// ---------------------------------------------------------------------------

class _Body extends StatelessWidget {
  const _Body({required this.page, required this.onLoadMore});

  final CommunityPage<CommunityClub> page;
  final Future<void> Function() onLoadMore;

  @override
  Widget build(BuildContext context) {
    final items = page.items;
    if (items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: <Widget>[
          const SizedBox(height: 32),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: Text(
                _l10nClubListEmpty,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          ),
        ],
      );
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: items.length + 1,
      itemBuilder: (context, index) {
        if (index == items.length) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: TextButton(
                onPressed: onLoadMore,
                child: const Text(_l10nClubListLoadMore),
              ),
            ),
          );
        }
        return _ClubRow(club: items[index]);
      },
    );
  }
}

/// A single accessible club-row (A7).
class _ClubRow extends StatelessWidget {
  const _ClubRow({required this.club});

  final CommunityClub club;

  @override
  Widget build(BuildContext context) {
    final textScaler = MediaQuery.textScalerOf(context);
    final nameStyle = TextStyle(
      fontSize: textScaler.scale(18),
      fontWeight: FontWeight.bold,
    );
    final visibilityLabel = _visibilityLabel(club.visibility);
    final memberLabel = '${club.memberCount}';
    return Semantics(
      container: true,
      label: '${club.name}. $visibilityLabel. $memberLabel members.',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).dividerColor,
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    club.name,
                    style: nameStyle,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$visibilityLabel · $memberLabel members',
                    style: TextStyle(fontSize: textScaler.scale(14)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Map a wire-string visibility to a localised label.
String _visibilityLabel(ClubVisibility visibility) {
  switch (visibility) {
    case ClubVisibility.private:
      return _l10nClubVisibilityPrivate;
    case ClubVisibility.discoverable:
      return _l10nClubVisibilityDiscoverable;
    case ClubVisibility.public:
      return _l10nClubVisibilityPublic;
  }
}

// ---------------------------------------------------------------------------
// Create-club dialog (ADR 0420 D7 — lives in this screen file).
// ---------------------------------------------------------------------------

typedef _CreateClubCallback =
    Future<void> Function({
      required String name,
      required String description,
      required ClubVisibility visibility,
      required List<String> tags,
      required String idempotencyKey,
    });

class _CreateClubDialog extends StatefulWidget {
  const _CreateClubDialog({required this.onCreate});

  final _CreateClubCallback onCreate;

  @override
  State<_CreateClubDialog> createState() => _CreateClubDialogState();
}

class _CreateClubDialogState extends State<_CreateClubDialog> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _description = TextEditingController();
  ClubVisibility _visibility = ClubVisibility.private;
  bool _submitting = false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(_l10nClubListCreate),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: _l10nClubListCreateName,
            ),
            maxLength: 60,
          ),
          TextField(
            controller: _description,
            decoration: const InputDecoration(
              labelText: _l10nClubListCreateDescription,
            ),
            maxLength: 2000,
            maxLines: 3,
          ),
          DropdownButtonFormField<ClubVisibility>(
            initialValue: _visibility,
            decoration: const InputDecoration(
              labelText: _l10nClubListCreateVisibility,
            ),
            items: <DropdownMenuItem<ClubVisibility>>[
              DropdownMenuItem<ClubVisibility>(
                value: ClubVisibility.private,
                child: const Text(_l10nClubVisibilityPrivate),
              ),
              DropdownMenuItem<ClubVisibility>(
                value: ClubVisibility.discoverable,
                child: const Text(_l10nClubVisibilityDiscoverable),
              ),
              DropdownMenuItem<ClubVisibility>(
                value: ClubVisibility.public,
                child: const Text(_l10nClubVisibilityPublic),
              ),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _visibility = v);
            },
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text(_l10nClubListCreateCancel),
        ),
        FilledButton(
          onPressed: _submitting
              ? null
              : () async {
                  setState(() => _submitting = true);
                  try {
                    await widget.onCreate(
                      name: _name.text.trim(),
                      description: _description.text,
                      visibility: _visibility,
                      tags: const <String>[],
                      idempotencyKey:
                          'create-${DateTime.now().microsecondsSinceEpoch}',
                    );
                    if (context.mounted) Navigator.of(context).pop();
                  } catch (_) {
                    if (context.mounted) {
                      setState(() => _submitting = false);
                    }
                  }
                },
          child: const Text(_l10nClubListCreateSubmit),
        ),
      ],
    );
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
              const Text(_l10nClubListError, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              TextButton(
                onPressed: onRetry,
                child: const Text(_l10nClubListRetry),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
