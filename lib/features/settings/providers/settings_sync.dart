import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/locale_provider.dart';
import '../../../core/theme/theme_mode_provider.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/settings_repository.dart';
import 'confidence_threshold_provider.dart';

/// Debounce for coalescing local settings changes before pushing them.
/// Overridden to [Duration.zero] in tests.
final settingsSyncDebounceProvider = Provider<Duration>(
  (_) => const Duration(milliseconds: 600),
);

/// Keeps the local settings and the signed-in user's cloud profile in sync.
///
/// - **On sign-in:** pull the cloud profile and apply it locally (the account
///   is the source of truth for a logged-in session).
/// - **On any local change while signed in:** push it (debounced).
///
/// Logged out, this is inert — the app keeps working fully offline. All network
/// calls are best-effort: if the server is unreachable, local settings stand
/// and the next change re-syncs.
class SettingsSync {
  SettingsSync(this._ref) {
    // React to sign-in / sign-out.
    _ref.listen(authControllerProvider, (prev, next) {
      final wasSignedIn = prev?.value != null;
      final isSignedIn = next.value != null;
      if (!wasSignedIn && isSignedIn) _pull();
    }, fireImmediately: true);

    // Push local edits (guarded so a pull's own writes don't echo back).
    _ref.listen(themeModeProvider, (_, _) => _onLocalChange());
    _ref.listen(localeProvider, (_, _) => _onLocalChange());
    _ref.listen(confidenceThresholdProvider, (_, _) => _onLocalChange());
  }

  final Ref _ref;
  Timer? _debounce;

  /// Signature of the values last known to match the server — used to suppress
  /// the echo when a pull applies remote values locally.
  String? _syncedSignature;

  bool get _signedIn => _ref.read(authControllerProvider).value != null;

  String _currentSignature() {
    final theme = _ref.read(themeModeProvider).name;
    final locale = _ref.read(localeProvider)?.languageCode ?? '';
    final threshold = _ref.read(confidenceThresholdProvider);
    return '$theme|$locale|$threshold';
  }

  Future<void> _pull() async {
    try {
      final remote = await _ref.read(settingsRepositoryProvider).fetch();
      // Mark these values as "already synced" BEFORE applying them, so the
      // resulting local-change notifications are recognised as an echo.
      _syncedSignature =
          '${remote.themeMode.name}|${remote.locale?.languageCode ?? ''}'
          '|${remote.confidenceThreshold}';
      _ref.read(themeModeProvider.notifier).setMode(remote.themeMode);
      _ref.read(localeProvider.notifier).set(remote.locale);
      _ref
          .read(confidenceThresholdProvider.notifier)
          .set(remote.confidenceThreshold);
    } catch (_) {
      // Offline / server down — keep local settings; next change re-syncs.
    }
  }

  void _onLocalChange() {
    if (!_signedIn) return;
    if (_currentSignature() == _syncedSignature) return; // echo of a pull
    _debounce?.cancel();
    _debounce = Timer(_ref.read(settingsSyncDebounceProvider), _push);
  }

  Future<void> _push() async {
    if (!_signedIn) return;
    final theme = _ref.read(themeModeProvider);
    final locale = _ref.read(localeProvider);
    final threshold = _ref.read(confidenceThresholdProvider);
    _syncedSignature = _currentSignature();
    try {
      await _ref.read(settingsRepositoryProvider).update({
        'theme_mode': theme.name,
        'locale': locale?.languageCode,
        'confidence_threshold': threshold,
      });
    } catch (_) {
      // Offline — the next local change will retry the push.
    }
  }
}

/// Instantiate once (watched at app root) to wire the listeners for the app's
/// lifetime.
final settingsSyncProvider = Provider<SettingsSync>((ref) => SettingsSync(ref));
