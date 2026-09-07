import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/locale_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../practice_generator/public.dart';
import '../data/active_plan_today_plan_repository.dart';
import '../domain/today_plan_repository.dart';
import '../domain/today_plan_snapshot.dart';

/// The Today Hub's plan source (R19, audit M4).
///
/// Until this round the production value was a hard-coded
/// [UnavailableTodayPlanRepository] and nothing in `lib/` overrode it, so an
/// activated plan never reached the app's landing tab. It now reads the SAME
/// `activePracticePlanProvider` the plan screens read, and translates its
/// three async outcomes explicitly:
///
///   * data with a plan  → the projection (`ActivePlanTodayPlanRepository`);
///   * data without one  → [UnavailableTodayPlanRepository];
///   * a read FAILURE    → [UnreadableTodayPlanRepository] — never "no
///     plan". `activePracticePlanProvider` surfaces a corrupt/unreadable
///     record as an `AsyncError` precisely so the UI can tell the two
///     apart; collapsing it here would undo that.
///
/// Loading maps to [UnavailableTodayPlanRepository] on purpose: the store is
/// on-device and settles within a frame or two, and the hub has no loading
/// state of its own — showing the honest zero-state briefly is better than
/// inventing a plan that may not exist. Tests keep overriding this provider
/// with a fake, exactly as before.
final todayPlanRepositoryProvider = Provider<TodayPlanRepository>((ref) {
  final activePlan = ref.watch(activePracticePlanProvider);
  if (activePlan.hasError) {
    return const UnreadableTodayPlanRepository();
  }
  final plan = activePlan.value;
  if (plan == null) {
    return const UnavailableTodayPlanRepository();
  }
  return ActivePlanTodayPlanRepository(
    controller: ref.watch(todayPlanControllerProvider),
    plan: plan,
    l10n: lookupAppLocalizations(_localeFor(ref.watch(localeProvider))),
  );
});

/// The locale the hub's plan copy is rendered in.
///
/// `localeProvider` is `null` for "follow the system", and a cloud-synced
/// settings row could carry a language this build does not ship; both fall
/// back to English rather than letting `lookupAppLocalizations` throw inside
/// a provider and take the whole tab down. Same fallback the Practice
/// Generator's own composition root uses for `PlanSetupController.locale`.
Locale _localeFor(Locale? preferred) {
  if (preferred == null) return const Locale('en');
  final isSupported = AppLocalizations.supportedLocales.any(
    (locale) => locale.languageCode == preferred.languageCode,
  );
  return isSupported ? Locale(preferred.languageCode) : const Locale('en');
}

final todayPlanSnapshotProvider = Provider<TodayPlanSnapshot>(
  (ref) => ref.watch(todayPlanRepositoryProvider).load(),
);
