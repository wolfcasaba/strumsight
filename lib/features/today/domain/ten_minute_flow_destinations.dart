import '../../../app/routing/app_route.dart';
import '../../practice/public.dart' show PracticeDefinition;
import 'ten_minute_flow.dart';

/// Where "start practising now" goes — the ONE rule both the ordinary Today
/// CTA (audit L1, E13-R17) and the 10-minute chain's play step share, so the
/// two can never drift into two different destinations.
///
/// TWO cases keep the Practice HUB, because neither can produce a setup
/// screen: an EMPTY catalog (no recommendation exists at all, ADR 0508 D4 —
/// never a setup route without a definition id) and a build with
/// `practiceEngineV2Enabled` off, where `/practice/setup` is not even
/// registered (E02-R12, `app_router.dart`).
String practiceStartLocation({
  required bool practiceEngineEnabled,
  required List<PracticeDefinition> catalog,
}) {
  if (!practiceEngineEnabled || catalog.isEmpty) {
    return AppRoutes.practiceHub;
  }
  return Uri(
    path: AppRoutes.practiceSetup,
    queryParameters: <String, String>{'id': catalog.first.id},
  ).toString();
}

/// The route a chain step sends the user to, or `null` when the step is
/// rendered in place on the Today hub.
///
/// [TenMinuteStep.review] deliberately has NO route: `/practice/result` is
/// registered as `PracticeResultFallback` (`app_router.dart`), i.e. the
/// "there is no result to show" screen unless the practice session itself
/// pushed one. Sending the user there from Today would be a dead end
/// dressed as a recap, so the recap is rendered on the hub instead and the
/// real `practice_result_screen` stays what the practice session ends on.
String? tenMinuteStepLocation(
  TenMinuteStep step, {
  required bool practiceEngineEnabled,
  required List<PracticeDefinition> catalog,
}) => switch (step) {
  // `/practice/tuner` — not the legacy `/tuner` — because the Today hub
  // itself is only registered inside the adaptive shell, where this path is
  // the tuner's own (unredirected) location.
  TenMinuteStep.tune => AppRoutes.practiceTuner,
  TenMinuteStep.play => practiceStartLocation(
    practiceEngineEnabled: practiceEngineEnabled,
    catalog: catalog,
  ),
  TenMinuteStep.review => null,
};
