import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/locale_provider.dart';
import '../../../core/theme/theme_mode_provider.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/settings_repository.dart';
import 'confidence_threshold_provider.dart';
import 'tuning_reference_provider.dart';

/// Debounce for coalescing local settings changes before pushing them.
/// Overridden to [Duration.zero] in tests.
final settingsSyncDebounceProvider = Provider<Duration>(
  (_) => const Duration(milliseconds: 600),
);

/// Backoff before retrying a push that failed (offline). Overridden in tests.
final settingsSyncRetryProvider = Provider<Duration>(
  (_) => const Duration(seconds: 10),
);

/// Keeps local settings and the signed-in user's cloud profile in sync.
///
/// - **Login / session restore** ⇒ pull the cloud profile and apply it locally
///   (the account is the source of truth for an existing session).
/// - **Register** ⇒ push the current LOCAL settings up as the new profile, so a
///   user who customised the app offline doesn't lose those on signup.
/// - **Any local change while signed in** ⇒ push it (debounced), with a bounded
///   retry so an offline edit is never silently dropped.
///
/// Logged out, this is inert — the app works fully offline. Synced fields:
/// theme, locale, confidence threshold, and tuning reference A4.
class SettingsSync {
  SettingsSync(this._ref) {
    // Drive sync from explicit auth events so register (adopt local) is
    // distinguished from login/restore (adopt remote).
    _ref.listen(authEventProvider, (_, next) {
      switch (next) {
        case AuthEvent.loggedIn:
          _pull();
        case AuthEvent.registered:
          _pushAll();
        case null:
          break;
      }
    });

    // Ensure a stored session restores at launch (triggers the event above).
    _ref.listen(authControllerProvider, (_, _) {}, fireImmediately: true);

    // Push local edits (guarded so a pull's own writes don't echo back).
    _ref.listen(themeModeProvider, (_, _) => _onLocalChange());
    _ref.listen(localeProvider, (_, _) => _onLocalChange());
    _ref.listen(confidenceThresholdProvider, (_, _) => _onLocalChange());
    _ref.listen(tuningReferenceProvider, (_, _) => _onLocalChange());
  }

  final Ref _ref;
  Timer? _debounce;

  /// True while a pull is applying remote values locally — suppresses the
  /// resulting change notifications so they don't bounce straight back.
  bool _applyingPull = false;

  /// Signature of the values last confirmed on the server (secondary echo
  /// guard, and what a successful push records).
  String? _syncedSignature;

  bool get _signedIn => _ref.read(authControllerProvider).value != null;

  String _currentSignature() {
    final theme = _ref.read(themeModeProvider).name;
    final locale = _ref.read(localeProvider)?.languageCode ?? '';
    final threshold = _ref.read(confidenceThresholdProvider);
    final a4 = _ref.read(tuningReferenceProvider);
    return '$theme|$locale|$threshold|$a4';
  }

  Map<String, dynamic> _currentPatch() {
    return {
      'theme_mode': _ref.read(themeModeProvider).name,
      'locale': _ref.read(localeProvider)?.languageCode,
      'confidence_threshold': _ref.read(confidenceThresholdProvider),
      'tuning_a4': _ref.read(tuningReferenceProvider),
    };
  }

  Future<void> _pull() async {
    try {
      final remote = await _ref.read(settingsRepositoryProvider).fetch();
      _applyingPull = true;
      _syncedSignature =
          '${remote.themeMode.name}|${remote.locale?.languageCode ?? ''}'
          '|${remote.confidenceThreshold}|${remote.tuningA4}';
      _ref.read(themeModeProvider.notifier).setMode(remote.themeMode);
      _ref.read(localeProvider.notifier).set(remote.locale);
      _ref
          .read(confidenceThresholdProvider.notifier)
          .set(remote.confidenceThreshold);
      _ref.read(tuningReferenceProvider.notifier).set(remote.tuningA4);
      // Let the resulting change-listeners flush while still suppressed.
      await Future<void>.delayed(Duration.zero);
    } catch (_) {
      // Offline / server down — keep local settings; a later change re-syncs.
    } finally {
      _applyingPull = false;
    }
  }

  /// Push current local settings up (used on register — local wins).
  Future<void> _pushAll() async {
    if (!_signedIn) return;
    await _sendPatch(_currentPatch(), _currentSignature());
  }

  void _onLocalChange() {
    if (!_signedIn || _applyingPull) return;
    if (_currentSignature() == _syncedSignature) return; // echo of a pull
    _debounce?.cancel();
    _debounce = Timer(_ref.read(settingsSyncDebounceProvider), _push);
  }

  Future<void> _push() async {
    if (!_signedIn) return;
    await _sendPatch(_currentPatch(), _currentSignature());
  }

  Future<void> _sendPatch(Map<String, dynamic> patch, String signature) async {
    try {
      await _ref.read(settingsRepositoryProvider).update(patch);
      // Only mark synced AFTER the server confirms — otherwise an offline edit
      // would be falsely recorded as synced and silently lost.
      _syncedSignature = signature;
    } catch (_) {
      // Offline — retry with a bounded backoff so the edit isn't dropped.
      _debounce?.cancel();
      _debounce = Timer(_ref.read(settingsSyncRetryProvider), _push);
    }
  }
}

/// Instantiate once (watched at app root) to wire the listeners for the app's
/// lifetime.
final settingsSyncProvider = Provider<SettingsSync>((ref) => SettingsSync(ref));
