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
/// **Localization (E13-R34, A10).** Every user-facing string
/// routes through ``AppLocalizations`` — the ``communityClubList*``
/// / ``communityClubVisibility*`` keys in
/// ``lib/l10n/features/community_{en,hu}.arb``. No
/// ``const String _l10nClub*`` constant remains in this file.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:strumsight/core/design_system/public.dart';

import '../../../../../core/foundation/app_failure.dart';
import '../../../../../l10n/app_localizations.dart';
import '../../../domain/entities/community_club.dart';
import '../../../domain/repositories/club_repository.dart';
import '../../../domain/repositories/community_page.dart';
import '../../../domain/value_objects/cursor_page.dart';
import '../../widgets/community_theme_scope.dart';

/// Map a wire visibility to its localized label (E13-R34, A10).
String communityClubVisibilityLabel(
  AppLocalizations localizations,
  ClubVisibility visibility,
) {
  switch (visibility) {
    case ClubVisibility.private:
      return localizations.communityClubVisibilityPrivate;
    case ClubVisibility.discoverable:
      return localizations.communityClubVisibilityDiscoverable;
    case ClubVisibility.public:
      return localizations.communityClubVisibilityPublic;
  }
}

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
    final localizations = AppLocalizations.of(context);

    return CommunityThemeScope(
      child: Scaffold(
        appBar: AppBar(
          title: Text(localizations.communityClubListTitle),
          actions: <Widget>[
            IconButton(
              tooltip: localizations.communityClubListCreate,
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
              localizations: localizations,
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
              localizations: localizations,
              onRetry: () async {
                ref.invalidate(clubListProvider(const CursorPage.initial()));
                await ref.read(
                  clubListProvider(const CursorPage.initial()).future,
                );
              },
            ),
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
  const _Body({
    required this.page,
    required this.localizations,
    required this.onLoadMore,
  });

  final CommunityPage<CommunityClub> page;
  final AppLocalizations localizations;
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
                localizations.communityClubListEmpty,
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
              child: SsButton(
                onPressed: () => onLoadMore(),
                label: localizations.communityClubListLoadMore,
              ),
            ),
          );
        }
        return _ClubRow(club: items[index], localizations: localizations);
      },
    );
  }
}

/// A single accessible club-row (A7).
class _ClubRow extends StatelessWidget {
  const _ClubRow({required this.club, required this.localizations});

  final CommunityClub club;
  final AppLocalizations localizations;

  @override
  Widget build(BuildContext context) {
    final textScaler = MediaQuery.textScalerOf(context);
    final nameStyle = TextStyle(
      fontSize: textScaler.scale(18),
      fontWeight: FontWeight.bold,
    );
    final visibilityLabel = communityClubVisibilityLabel(
      localizations,
      club.visibility,
    );
    final memberCountLabel = localizations.communityClubMemberCountLabel(
      visibilityLabel,
      club.memberCount,
    );
    return Semantics(
      container: true,
      label: '${club.name}. $memberCountLabel.',
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
                    memberCountLabel,
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
    final localizations = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(localizations.communityClubListCreate),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextField(
            controller: _name,
            decoration: InputDecoration(
              labelText: localizations.communityClubListCreateName,
            ),
            maxLength: 60,
          ),
          TextField(
            controller: _description,
            decoration: InputDecoration(
              labelText: localizations.communityClubListCreateDescription,
            ),
            maxLength: 2000,
            maxLines: 3,
          ),
          DropdownButtonFormField<ClubVisibility>(
            initialValue: _visibility,
            decoration: InputDecoration(
              labelText: localizations.communityClubListCreateVisibility,
            ),
            items: <DropdownMenuItem<ClubVisibility>>[
              for (final visibility in ClubVisibility.values)
                DropdownMenuItem<ClubVisibility>(
                  value: visibility,
                  child: Text(
                    communityClubVisibilityLabel(localizations, visibility),
                  ),
                ),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _visibility = v);
            },
          ),
        ],
      ),
      actions: <Widget>[
        SsButton(
          variant: SsButtonVariant.tertiary,
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          label: localizations.communityClubListCreateCancel,
        ),
        SsButton(
          loading: _submitting,
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
          label: localizations.communityClubListCreateSubmit,
        ),
      ],
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
                localizations.communityClubListError,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              SsButton(
                onPressed: () => onRetry(),
                label: localizations.communityClubListRetry,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
