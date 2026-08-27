import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routing/app_route.dart';
import '../../../core/design_system/public.dart';
import '../../../l10n/app_localizations.dart';
import '../domain/library_item.dart';
import '../providers/library_v2_providers.dart';
import '../widgets/library_item_tile.dart';
import '../widgets/library_theme_scope.dart';

/// The unified library list (UI-40, `/profile/library`) — search, type
/// filter and a type-safe list-detail push (A1).
final class UnifiedLibraryScreen extends ConsumerWidget {
  const UnifiedLibraryScreen({super.key});

  void _openItem(BuildContext context, LibraryItem item) {
    if (item is CorruptLibraryItem) return;
    context.push(
      AppRoutes.profileLibrarySession.replaceFirst(':sessionId', item.id),
      extra: item,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final visible = ref.watch(libraryV2VisibleItemsProvider);
    final typeFilter = ref.watch(libraryV2TypeFilterProvider);

    return LibraryThemeScope(
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.libraryV2Title)),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SsTextField(
                  label: l10n.libraryV2SearchLabel,
                  onChanged: (value) => ref
                      .read(libraryV2SearchQueryProvider.notifier)
                      .setQuery(value),
                ),
                const SizedBox(height: 12),
                SsChoice<LibraryItemType?>(
                  style: SsChoiceStyle.chip,
                  value: typeFilter,
                  options: [
                    SsChoiceOption(value: null, label: l10n.libraryV2FilterAll),
                    SsChoiceOption(
                      value: LibraryItemType.practice,
                      label: l10n.libraryV2TypePractice,
                    ),
                    SsChoiceOption(
                      value: LibraryItemType.analysis,
                      label: l10n.libraryV2TypeAnalysis,
                    ),
                    SsChoiceOption(
                      value: LibraryItemType.song,
                      label: l10n.libraryV2TypeSong,
                    ),
                    SsChoiceOption(
                      value: LibraryItemType.setlist,
                      label: l10n.libraryV2TypeSetlist,
                    ),
                  ],
                  onChanged: (value) => ref
                      .read(libraryV2TypeFilterProvider.notifier)
                      .setFilter(value),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: visible.when(
                    loading: () => const Center(
                      child: CircularProgressIndicator(
                        key: ValueKey('library-v2-loading'),
                      ),
                    ),
                    error: (error, stackTrace) =>
                        Center(child: Text(l10n.libraryV2LoadFailed)),
                    data: (items) => items.isEmpty
                        ? SsEmptyState(
                            icon: Icons.folder_open_outlined,
                            title: l10n.libraryV2EmptyTitle,
                            message: l10n.libraryV2EmptyMessage,
                            actionLabel: l10n.libraryV2EmptyAction,
                            onAction: () => ref
                                .read(libraryV2ItemsProvider.notifier)
                                .reload(),
                          )
                        : ListView.builder(
                            key: const ValueKey('library-v2-list'),
                            itemCount: items.length,
                            itemBuilder: (context, index) {
                              final item = items[index];
                              return LibraryItemTile(
                                item: item,
                                onTap: item is CorruptLibraryItem
                                    ? null
                                    : () => _openItem(context, item),
                              );
                            },
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
