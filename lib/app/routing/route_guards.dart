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
String? onboardingRedirect({required bool seen, required String location}) {
  if (!seen && location != AppRoutes.welcome) {
    return AppRoutes.welcome;
  }
  if (seen && location == AppRoutes.welcome) {
    return AppRoutes.live;
  }
  return null;
}
