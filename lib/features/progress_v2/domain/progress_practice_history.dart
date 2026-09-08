import 'dart:collection';

import '../../practice/public.dart';

/// The practice history as the composition layer resolved it, carrying the
/// one bit a bare list cannot: whether the READ FAILED (M9, re-audit
/// 2026-09-08).
///
/// Before this round `practiceHistoryV2ListProvider` flattened a failed read
/// into an empty list, so an unreadable history store reached the Progress
/// V2 dashboard as "you have never practiced" — a corrupt store and a brand
/// new user rendered the same hero. The failure now survives as far as the
/// screen, which says it out loud and offers a retry.
///
/// **Why a `List` subtype and not a plain record/value object.** The
/// projection is built inside `lib/app/routing/app_router.dart`, which is
/// frozen for this round (a concurrent round owns it), and the router's call
/// is a pure `practiceHistory: ref.watch(progressPracticeHistoryProvider)`
/// pass-through — so the history argument is the ONLY channel the failure
/// can travel on without editing the router. Staying a real
/// `List<PracticeHistoryEntry>` also keeps every existing reader (the e2e
/// walkthrough's `hasLength`, the projection builders, the fixtures that
/// pass plain lists) working unchanged: a plain list simply means what it
/// always meant — "this IS the history".
final class ProgressPracticeHistory extends ListBase<PracticeHistoryEntry> {
  /// A history that was read successfully — possibly empty, which honestly
  /// means "no sessions yet".
  ProgressPracticeHistory.loaded(List<PracticeHistoryEntry> entries)
    : _entries = List<PracticeHistoryEntry>.unmodifiable(entries),
      isUnavailable = false;

  /// The read failed. Empty, but NEVER "no sessions yet".
  ProgressPracticeHistory.unavailable()
    : _entries = const <PracticeHistoryEntry>[],
      isUnavailable = true;

  final List<PracticeHistoryEntry> _entries;

  /// True when the practice-history read failed. Consumers that only need
  /// entries can keep ignoring this; the ones that would otherwise present
  /// emptiness as a fact must not.
  final bool isUnavailable;

  @override
  int get length => _entries.length;

  @override
  set length(int newLength) =>
      throw UnsupportedError('ProgressPracticeHistory is read-only.');

  @override
  PracticeHistoryEntry operator [](int index) => _entries[index];

  @override
  void operator []=(int index, PracticeHistoryEntry value) =>
      throw UnsupportedError('ProgressPracticeHistory is read-only.');
}
