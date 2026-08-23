import 'app_route.dart';

enum UnsavedEditorDecision { stay, discard, save }

/// Pure route-guard decision. A dirty editor may leave only after an explicit
/// discard choice or a successfully completed save.
bool mayLeaveEditor({
  required bool dirty,
  required UnsavedEditorDecision decision,
  required bool saveSucceeded,
}) {
  if (!dirty) return true;
  return decision == UnsavedEditorDecision.discard ||
      (decision == UnsavedEditorDecision.save && saveSucceeded);
}

/// Returns the onboarding redirect target, or `null` when navigation may
/// continue.
///
/// Redirects are idempotent: applying this function again to any non-null
/// result returns `null`, which prevents redirect loops.
///
/// [home] is where a seen-onboarding user lands after `/welcome`. It
/// defaults to [AppRoutes.live] so every existing caller (in particular the
/// unmodified `test/app/routing/route_guards_test.dart`) is unaffected; the
/// router passes [AppRoutes.today] here when `adaptiveShellEnabled` is on
/// (brief §0.0 D14/4).
String? onboardingRedirect({
  required bool seen,
  required String location,
  String home = AppRoutes.live,
}) {
  if (!seen && location != AppRoutes.welcome) {
    return AppRoutes.welcome;
  }
  if (seen && location == AppRoutes.welcome) {
    return home;
  }
  return null;
}
