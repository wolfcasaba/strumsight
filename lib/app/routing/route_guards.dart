import 'app_route.dart';

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
