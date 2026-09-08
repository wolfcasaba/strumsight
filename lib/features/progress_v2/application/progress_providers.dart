import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../practice/public.dart';
import '../domain/progress_practice_history.dart';

/// The Progress V2 feature's own Riverpod composition layer (ADR 0500 §5.1,
/// mirrors `gamification_providers.dart` / ADR 0496 §1). The router stays a
/// pure consumer: it reads these providers, resolves localization (the one
/// thing this layer has no `BuildContext` for — same split as
/// `gamification_providers.dart`'s `_rewardEventFor`/`_localizedRewardInboxItems`),
/// and calls `progress_projection_builder.dart`'s pure builder functions.

/// Dedicated "now" provider (rather than an inline `DateTime.now()` call in
/// the router) so a test can override it deterministically — same shape as
/// `todayEpochDayProvider` (gamification_providers.dart).
final progressNowProvider = Provider<DateTime>((_) => DateTime.now().toUtc());

/// The loaded V2 practice history — empty while loading, and explicitly
/// UNAVAILABLE when the read failed (M9, re-audit 2026-09-08).
///
/// `practiceHistoryV2ListProvider` surfaces a failed read as an `AsyncError`
/// precisely so this layer can tell "the store could not be read" apart from
/// "there are no sessions yet"; the previous `.value ?? []` collapsed the two
/// and the dashboard showed a corrupt store as a brand new user. Loading
/// still maps to an empty, AVAILABLE history: the store is on-device and
/// settles within a frame or two (the same reasoning
/// `todayPlanRepositoryProvider` records for its own loading state).
///
/// The DECLARED type stays `List<PracticeHistoryEntry>` while the value is
/// always a [ProgressPracticeHistory]: the router hands this straight to the
/// projection builders, and every existing `overrideWithValue(<plain list>)`
/// in the suite keeps its exact previous meaning — "this IS the history".
///
/// Riverpod 3.3.2 — `.value` is nullable, never `.valueOrNull`.
final progressPracticeHistoryProvider = Provider<List<PracticeHistoryEntry>>((
  ref,
) {
  final history = ref.watch(practiceHistoryV2ListProvider);
  if (history.hasError) return ProgressPracticeHistory.unavailable();
  return ProgressPracticeHistory.loaded(
    history.value ?? const <PracticeHistoryEntry>[],
  );
});

/// Progress V2 is 100% local (§5.7): the dashboard reads only the local
/// practice-history repository and never syncs with an account layer, so a
/// "not yet synced" state cannot occur here. A measured constant, not a
/// placeholder standing in for a missing sync-status source.
const bool progressV2IsOffline = false;

/// `MasteryMilestone.titleKey`/`descriptionKey` → localized display text, an
/// EXPLICIT switch (§5.6 — dynamic ARB-key lookup is forbidden). Takes
/// [AppLocalizations] as a plain value rather than `BuildContext`, so it
/// stays callable from the router's `Consumer` builder, which has `context`
/// (mirrors `buildR06XpComponents`, gamification_providers.dart precedent).
String progressV2LocalizedText(
  AppLocalizations l10n,
  String key,
) => switch (key) {
  'masteryChordTransitionTitle' => l10n.masteryChordTransitionTitle,
  'masteryChordTransitionDescription' => l10n.masteryChordTransitionDescription,
  'masteryRhythmAccuracyTitle' => l10n.masteryRhythmAccuracyTitle,
  'masteryRhythmAccuracyDescription' => l10n.masteryRhythmAccuracyDescription,
  'masteryStrumConsistencyTitle' => l10n.masteryStrumConsistencyTitle,
  'masteryStrumConsistencyDescription' =>
    l10n.masteryStrumConsistencyDescription,
  _ => key,
};
