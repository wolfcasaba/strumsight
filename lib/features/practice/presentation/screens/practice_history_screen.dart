/// The Practice history list (SDD UI-22, E13-R22).
///
/// Reads [practiceHistoryEntriesProvider], which is backed by
/// [practiceHistoryRepositoryProvider] — local storage only (ADR 0283
/// §Döntés 3), so this screen renders identically online or offline (A4). A
/// single corrupt record never takes the rest of the list down: the
/// repository already isolates decode failures at read time
/// (`JsonCollectionStore`, A3) — this screen renders whatever entries
/// survive that filter, unaware of how many (if any) were skipped.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../domain/model/practice_history_entry.dart';
import '../../domain/model/practice_mode.dart';
import '../providers/practice_result_providers.dart';
import '../widgets/practice_mode_card.dart' show practiceModeLabel;
import 'practice_result_screen.dart';

class PracticeHistoryScreen extends ConsumerWidget {
  const PracticeHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(practiceHistoryEntriesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.practiceHistoryTitle)),
      body: SafeArea(
        child: switch (async) {
          AsyncData(:final value) => value.fold(
            onSuccess: (entries) => _HistoryBody(entries: entries),
            onFailure: (_) => const _HistoryError(),
          ),
          AsyncError() => const _HistoryError(),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }
}

class _HistoryError extends StatelessWidget {
  const _HistoryError();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 48,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 12),
          Text(
            l10n.practiceHistoryErrorTitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            l10n.practiceHistoryErrorBody,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: Text(l10n.practiceHistoryErrorAction),
          ),
        ],
      ),
    );
  }
}

class _HistoryEmpty extends StatelessWidget {
  const _HistoryEmpty();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history,
            size: 48,
            color: Theme.of(context).colorScheme.secondary,
          ),
          const SizedBox(height: 12),
          Text(
            l10n.practiceHistoryEmptyTitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            l10n.practiceHistoryEmptyBody,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: Text(l10n.practiceHistoryEmptyAction),
          ),
        ],
      ),
    );
  }
}

class _HistoryBody extends ConsumerWidget {
  const _HistoryBody({required this.entries});
  final List<PracticeHistoryEntry> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (entries.isEmpty) {
      return const _HistoryEmpty();
    }
    final filter = ref.watch(practiceHistoryModeFilterProvider);
    final filtered = filter == null
        ? entries
        : entries
              .where((entry) => entry.modeCode == filter.code)
              .toList(growable: false);
    return Column(
      children: [
        _ModeFilterRow(current: filter, modesPresent: entries),
        Expanded(
          child: filtered.isEmpty
              ? const _HistoryEmpty()
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) =>
                      _HistoryRow(entry: filtered[index]),
                ),
        ),
      ],
    );
  }
}

class _ModeFilterRow extends ConsumerWidget {
  const _ModeFilterRow({required this.current, required this.modesPresent});
  final PracticeMode? current;
  final List<PracticeHistoryEntry> modesPresent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final present = <PracticeMode>{
      for (final entry in modesPresent)
        if (PracticeMode.values.any((m) => m.code == entry.modeCode))
          PracticeMode.values.firstWhere((m) => m.code == entry.modeCode),
    };
    final notifier = ref.read(practiceHistoryModeFilterProvider.notifier);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(l10n.practiceHistoryFilterAll),
              selected: current == null,
              onSelected: (_) => notifier.set(null),
            ),
          ),
          for (final mode in present)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(practiceModeLabel(l10n, mode)),
                selected: current == mode,
                onSelected: (_) => notifier.set(mode),
              ),
            ),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry});
  final PracticeHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final mode = PracticeMode.values.firstWhere(
      (m) => m.code == entry.modeCode,
      orElse: () => PracticeMode.strumPattern,
    );
    return Card(
      child: ListTile(
        minVerticalPadding: 14,
        title: Text(
          entry.displayTitle.isEmpty
              ? practiceModeLabel(l10n, mode)
              : entry.displayTitle,
        ),
        subtitle: Text(
          entry.totalTargets > 0
              ? l10n.practiceHistoryRowSubtitle(
                  entry.resolvedTargets,
                  entry.totalTargets,
                )
              : practiceModeLabel(l10n, mode),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => PracticeResultScreen(entry: entry),
          ),
        ),
      ),
    );
  }
}
