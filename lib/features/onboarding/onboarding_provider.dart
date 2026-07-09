import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether the first-run onboarding has been completed. Loaded once at boot
/// (see `main`) and overridden into the provider so the router can gate on it
/// synchronously with no flicker for returning users.
///
/// Default is **true** (assume seen) so widget tests and any un-overridden
/// context skip onboarding; `main` overrides it with the real persisted flag,
/// which is only false on a genuine first launch.
class OnboardingController extends Notifier<bool> {
  OnboardingController(this._initial);

  /// Preference key + a static loader `main` uses before `runApp`.
  static const String key = 'onboarding_seen_v1';

  /// Read the persisted flag. Returns false only on a true first run; on any
  /// error we assume seen (never trap a returning user in onboarding).
  static Future<bool> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(key) ?? false;
    } catch (_) {
      return true;
    }
  }

  final bool _initial;

  @override
  bool build() => _initial;

  /// Mark onboarding complete and persist it.
  Future<void> complete() async {
    state = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, true);
    } catch (_) {
      // Best-effort; stays complete for this session regardless.
    }
  }
}

final onboardingSeenProvider =
    NotifierProvider<OnboardingController, bool>(() => OnboardingController(true));
