import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../practice/public.dart';

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

/// The loaded V2 practice history, falling back to empty while loading or on
/// a failed load. `practiceHistoryV2ListProvider` (practice feature) already
/// owns the load/failure handling; this applies the same `.value ?? []`
/// fallback used elsewhere on the tree (Riverpod 3.3.2 — `.value` is
/// nullable, never `.valueOrNull`).
final progressPracticeHistoryProvider = Provider<List<PracticeHistoryEntry>>((
  ref,
) {
  return ref.watch(practiceHistoryV2ListProvider).value ??
      const <PracticeHistoryEntry>[];
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
