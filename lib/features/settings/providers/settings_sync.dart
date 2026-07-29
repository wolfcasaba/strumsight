import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/foundation/app_failure.dart';
import '../../../core/foundation/app_result.dart';
import '../../../core/i18n/locale_provider.dart';
import '../../../core/logging/logger_provider.dart';
import '../../../core/theme/theme_mode_provider.dart';
import '../../auth/public.dart';
import '../data/settings_repository.dart';
import 'confidence_threshold_provider.dart';
import 'tuning_reference_provider.dart';

/// Debounce for coalescing local settings changes before pushing them.
/// Overridden to [Duration.zero] in tests.
final settingsSyncDebounceProvider = Provider<Duration>(
  (_) => const Duration(milliseconds: 600),
);

/// Keeps local settings and the signed-in user's cloud profile in sync.
///
/// - **Login / session restore** ⇒ pull the cloud profile and apply it locally
///   (the account is the source of truth for an existing session).
/// - **Register** ⇒ push the current LOCAL settings up as the new profile, so a
///   user who customised the app offline doesn't lose those on signup.
/// - **Any local change while signed in** ⇒ push it once (debounced). A later
///   genuine edit sends the latest full profile; writes are never replayed
///   automatically.
///
/// Logged out, this is inert — the app works fully offline. Synced fields:
/// theme, locale, confidence threshold, and tuning reference A4.
class SettingsSync {
  SettingsSync(this._ref) {
    if (!_ref.read(accountEnabledProvider)) return;

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
    _ref.listen(authControllerProvider, (_, next) {
      _authRevision++;
      if (next.value == null) {
        _debounce?.cancel();
        _pushPending = false;
        _forcePendingPush = false;
        _syncedSignature = null;
      }
    }, fireImmediately: true);

    // Push local edits (guarded so a pull's own writes don't echo back).
    _ref.listen(themeModeProvider, (_, _) => _onLocalChange());
    _ref.listen(localeProvider, (_, _) => _onLocalChange());
    _ref.listen(confidenceThresholdProvider, (_, _) => _onLocalChange());
    _ref.listen(tuningReferenceProvider, (_, _) => _onLocalChange());
    _ref.onDispose(() => _debounce?.cancel());
  }

  final Ref _ref;
  Timer? _debounce;
  int _authRevision = 0;
  int _localRevision = 0;
  int _pullRevision = 0;
  bool _pushInFlight = false;
  bool _pushPending = false;
  bool _forcePendingPush = false;

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

  Map<String, Object?> _currentPatch() {
    return {
      'theme_mode': _ref.read(themeModeProvider).name,
      'locale': _ref.read(localeProvider)?.languageCode,
      'confidence_threshold': _ref.read(confidenceThresholdProvider),
      'tuning_a4': _ref.read(tuningReferenceProvider),
    };
  }

  Future<void> _pull() async {
    final pullRevision = ++_pullRevision;
    final authRevision = _authRevision;
    final localRevision = _localRevision;
    final localSignature = _currentSignature();
    final result = await _ref.read(settingsRepositoryProvider).fetch();
    if (!_ref.mounted ||
        pullRevision != _pullRevision ||
        authRevision != _authRevision ||
        localRevision != _localRevision ||
        localSignature != _currentSignature()) {
      return;
    }
    switch (result) {
      case Failure(:final error):
        _ref
            .read(appLoggerProvider)
            .warning(
              'settings.sync_pull_failed',
              fields: {'code': error.code, 'retryable': error.retryable},
            );
        if (_isExpiredSession(error)) {
          await _ref.read(authControllerProvider.notifier).invalidateSession();
        }
        return;
      case Success(:final value):
        if (!_signedIn) return;
        final remoteSignature =
            '${value.themeMode.name}|${value.locale?.languageCode ?? ''}'
            '|${value.confidenceThreshold}|${value.tuningA4}';
        final localRevisionAtApply = _localRevision;

        // Every notifier publishes its in-memory state before its first await.
        // Start all four setters in one synchronous turn so no user edit can
        // land between fields and be overwritten by a later remote setter.
        _applyingPull = true;
        late final List<Future<void>> persistence;
        try {
          persistence = [
            _ref.read(themeModeProvider.notifier).setMode(value.themeMode),
            _ref.read(localeProvider.notifier).set(value.locale),
            _ref
                .read(confidenceThresholdProvider.notifier)
                .set(value.confidenceThreshold),
            _ref.read(tuningReferenceProvider.notifier).set(value.tuningA4),
          ];
          _syncedSignature = remoteSignature;
        } finally {
          _applyingPull = false;
        }
        await Future.wait(persistence);
        if (!_ref.mounted || authRevision != _authRevision || !_signedIn) {
          return;
        }

        // A genuine edit may have arrived while the four persistence futures
        // were pending. Re-persist the latest complete snapshot after the old
        // writes, repeating only if another edit lands during reconciliation.
        // This prevents a delayed remote write from winning on disk.
        if (_localRevision != localRevisionAtApply) {
          await _reconcileLocalPersistence(authRevision);
        }
        if (!_ref.mounted || authRevision != _authRevision || !_signedIn) {
          return;
        }
        if (_currentSignature() != _syncedSignature) {
          _schedulePush();
        }
    }
  }

  Future<void> _reconcileLocalPersistence(int authRevision) async {
    while (_ref.mounted && authRevision == _authRevision && _signedIn) {
      final revision = _localRevision;
      final theme = _ref.read(themeModeProvider);
      final locale = _ref.read(localeProvider);
      final confidence = _ref.read(confidenceThresholdProvider);
      final tuning = _ref.read(tuningReferenceProvider);

      _applyingPull = true;
      late final List<Future<void>> persistence;
      try {
        persistence = [
          _ref.read(themeModeProvider.notifier).setMode(theme),
          _ref.read(localeProvider.notifier).set(locale),
          _ref.read(confidenceThresholdProvider.notifier).set(confidence),
          _ref.read(tuningReferenceProvider.notifier).set(tuning),
        ];
      } finally {
        _applyingPull = false;
      }
      await Future.wait(persistence);
      if (!_ref.mounted ||
          authRevision != _authRevision ||
          !_signedIn ||
          revision == _localRevision) {
        return;
      }
    }
  }

  /// Push current local settings up (used on register — local wins).
  Future<void> _pushAll() => _queuePush(force: true);

  void _onLocalChange() {
    if (_applyingPull) return;
    _localRevision++;
    if (!_signedIn) return;
    if (!_pushInFlight && _currentSignature() == _syncedSignature) {
      _debounce?.cancel();
      return;
    }
    _schedulePush();
  }

  void _schedulePush() {
    _debounce?.cancel();
    _debounce = Timer(_ref.read(settingsSyncDebounceProvider), () {
      _debounce = null;
      unawaited(_push());
    });
  }

  Future<void> _push() => _queuePush();

  /// Serializes full-profile PUTs. A genuine edit received during an in-flight
  /// request marks the queue dirty; once that request finishes, exactly one
  /// latest snapshot follows it. Failed writes are not replayed unless such a
  /// later edit actually occurred.
  Future<void> _queuePush({bool force = false}) async {
    if (!_signedIn) return;
    _pushPending = true;
    _forcePendingPush = _forcePendingPush || force;
    if (_pushInFlight) return;

    _pushInFlight = true;
    try {
      while (_ref.mounted && _pushPending) {
        _pushPending = false;
        final forceThisPush = _forcePendingPush;
        _forcePendingPush = false;
        if (!_signedIn) break;

        final signature = _currentSignature();
        if (!forceThisPush && signature == _syncedSignature) continue;
        await _sendPatch(_currentPatch(), signature);
      }
    } finally {
      _pushInFlight = false;
    }
  }

  Future<void> _sendPatch(Map<String, Object?> patch, String signature) async {
    final authRevision = _authRevision;
    final result = await _ref.read(settingsRepositoryProvider).update(patch);
    if (!_ref.mounted || authRevision != _authRevision) return;
    switch (result) {
      case Success():
        // Only mark synced AFTER the server confirms — otherwise an offline
        // edit would be falsely recorded as synced and silently lost.
        _syncedSignature = signature;
      case Failure(:final error):
        _ref
            .read(appLoggerProvider)
            .warning(
              'settings.sync_push_failed',
              fields: {'code': error.code, 'retryable': error.retryable},
            );
        if (_isExpiredSession(error)) {
          await _ref.read(authControllerProvider.notifier).invalidateSession();
        }
    }
  }

  static bool _isExpiredSession(AppFailure error) =>
      error is AuthenticationFailure &&
      error.code == FailureCode.authSessionExpired;
}

/// Instantiate once (watched at app root) to wire the listeners for the app's
/// lifetime.
final settingsSyncProvider = Provider<SettingsSync>((ref) => SettingsSync(ref));
