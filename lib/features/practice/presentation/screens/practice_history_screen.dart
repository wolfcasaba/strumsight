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

import '../../../../core/design_system/public.dart';
import '../../../../core/foundation/app_failure.dart';
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
            onFailure: (failure) => _HistoryError(
              failure: failure,
              onRetry: () => ref.invalidate(practiceHistoryEntriesProvider),
            ),
          ),
          // A raw future exception (not an `AppResult.failure`) should never
          // happen — `LocalPracticeHistoryRepository.load()` catches every
          // storage error and returns it as a value — but if it ever does,
          // this screen only ever reads local storage, so a storage failure
          // is the accurate default (E15-R04 review MAJOR-2).
          AsyncError() => _HistoryError(
            failure: const StorageFailure(code: FailureCode.storageRead),
            onRetry: () => ref.invalidate(practiceHistoryEntriesProvider),
          ),
          _ => const _HistoryLoading(),
        },
      ),
    );
  }
}

class _HistoryLoading extends StatelessWidget {
  const _HistoryLoading();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      container: true,
      label: l10n.practiceHistoryLoading,
      child: ListView.separated(
        padding: const EdgeInsets.all(SsSpacing.space4),
        itemCount: 6,
        separatorBuilder: (_, _) => const SizedBox(height: SsSpacing.space2),
        itemBuilder: (_, _) =>
            const SsSkeleton(width: double.infinity, height: 72),
      ),
    );
  }
}

class _HistoryError extends StatelessWidget {
  const _HistoryError({required this.failure, required this.onRetry});
  final AppFailure failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SsFailureState(
      presentation: SsFailurePresentation.from(
        _HistoryFailureL10n(l10n),
        failure,
      ),
      onRetry: onRetry,
    );
  }
}

/// [SsFailurePresentation.from] decides the title/message from
/// [AppFailure.code] alone, and its actions from [AppFailure.retryable] —
/// there is no override parameter, and its constructor is private to
/// `failure_presentation.dart`. This screen keeps its own established copy
/// (`practiceHistoryErrorTitle`/`Body`) instead of the generic storage
/// strings by routing only those two lookups (plus the two action labels a
/// storage failure can produce) through the screen's ARB keys — every other
/// getter delegates to the real [_inner] localisations, unused here since
/// this screen only ever shows storage failures (E15-R04 review MAJOR-1).
class _HistoryFailureL10n implements AppLocalizations {
  const _HistoryFailureL10n(this._inner);
  final AppLocalizations _inner;

  @override
  String get dsFailureStorageTitle => _inner.practiceHistoryErrorTitle;

  @override
  String get dsFailureStorageMessage => _inner.practiceHistoryErrorBody;

  @override
  String get dsFailureRetryAction => _inner.dsFailureRetryAction;

  @override
  String get dsFailureContactSupportAction =>
      _inner.dsFailureContactSupportAction;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _HistoryEmpty extends StatelessWidget {
  const _HistoryEmpty();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SsEmptyState(
      icon: Icons.history,
      title: l10n.practiceHistoryEmptyTitle,
      message: l10n.practiceHistoryEmptyBody,
      actionLabel: l10n.practiceHistoryEmptyAction,
      onAction: () => Navigator.of(context).maybePop(),
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
                  padding: const EdgeInsets.all(SsSpacing.space4),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: SsSpacing.space2),
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
      padding: const EdgeInsets.fromLTRB(
        SsSpacing.space4,
        SsSpacing.space3,
        SsSpacing.space4,
        SsSpacing.space1,
      ),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: SsSpacing.space2),
            child: ChoiceChip(
              label: Text(l10n.practiceHistoryFilterAll),
              selected: current == null,
              onSelected: (_) => notifier.set(null),
            ),
          ),
          for (final mode in present)
            Padding(
              padding: const EdgeInsets.only(right: SsSpacing.space2),
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
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
    final mode = PracticeMode.values.firstWhere(
      (m) => m.code == entry.modeCode,
      orElse: () => PracticeMode.strumPattern,
    );
    return SsSurface(
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => PracticeResultScreen(entry: entry),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: SsSpacing.space4,
            vertical: SsSpacing.space3,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      entry.displayTitle.isEmpty
                          ? practiceModeLabel(l10n, mode)
                          : entry.displayTitle,
                      style: typography.labelLarge.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: SsSpacing.space1),
                    Text(
                      entry.totalTargets > 0
                          ? l10n.practiceHistoryRowSubtitle(
                              entry.resolvedTargets,
                              entry.totalTargets,
                            )
                          : practiceModeLabel(l10n, mode),
                      style: typography.bodyMedium.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: colors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
