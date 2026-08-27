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

/// The observable state of the settings cloud sync (§0.0.B/B3 — additive,
/// read-only). `synced` also covers "nothing to sync" (logged out, or no
/// edit since the last confirmed push): there is no separate "idle" state,
/// because the UI only needs to distinguish "safe" from "needs attention".
///
/// This does NOT change when a write goes out or how failures are handled —
/// it only narrates the existing, unchanged push/pull state machine so the
/// settings screen can show it. [failed] is cleared back to [synced] the
/// moment a push actually confirms — including a push from
/// [SettingsSync.retryFailedPush] (A4), never from a timer.
enum SettingsSyncStatus { synced, pending, failed }

/// Read-only outside this file: only [SettingsSync] (via [_SettingsSyncStatusNotifier.publish])
/// writes to it.
class _SettingsSyncStatusNotifier extends Notifier<SettingsSyncStatus> {
  @override
  SettingsSyncStatus build() => SettingsSyncStatus.synced;

  void publish(SettingsSyncStatus status) => state = status;
}

final settingsSyncStatusProvider =
    NotifierProvider<_SettingsSyncStatusNotifier, SettingsSyncStatus>(
      _SettingsSyncStatusNotifier.new,
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
        _lastPushFailed = false;
        // Nothing can be "pending"/"failed" while logged out — the account
        // layer is inert (class doc above); [_computeStatus] would already
        // resolve to this on its own, but publishing directly avoids waiting
        // on the microtask for a state transition this immediate.
        _republishStatus();
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

  /// Whether the LAST push attempt (for the signature still unconfirmed, if
  /// any) came back a [Failure]. Cleared the moment a push [Success]es, and
  /// irrelevant once the dirty edit it applied to is confirmed or reverted —
  /// [_computeStatus] only consults it while [_currentSignature] still
  /// differs from [_syncedSignature].
  bool _lastPushFailed = false;

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
        if (!_ref.mounted) return;
        if (authRevision != _authRevision) {
          // The session changed while these writes were in flight, so what we
          // just put on disk belongs to the PREVIOUS account — and it landed
          // after the current account's own pull already wrote. Re-persist the
          // live snapshot so the file agrees with what the app is showing
          // (round 216: the in-memory state was right, only the disk lied).
          await _persistSnapshot();
          return;
        }
        if (!_signedIn) return;

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

  /// Write the CURRENT in-memory settings back, whatever the session state is.
  ///
  /// Used when a stale write has just landed: the notifiers are the source of
  /// truth for this session, so the file has to be brought back to them.
  Future<void> _persistSnapshot() async {
    if (!_ref.mounted) return;
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
      // Javító kör 1, F2/M2: this used to return WITHOUT republishing —
      // if the user edited back to the last-confirmed value inside the
      // debounce window, the status stayed on whatever it was published as
      // for the abandoned edit (typically "pending"/"Saving…") forever,
      // since no push ever went out to resolve it. [_computeStatus] reads
      // the live signature, so this always resolves to the true state
      // (`synced`, or `pending`/`failed` if an unrelated push is still
      // in-flight/queued).
      _debounce?.cancel();
      _republishStatus();
      return;
    }
    _republishStatus();
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

  /// User-initiated retry (A4, §0.0.B/B3): the SAME push path as any other
  /// edit — no timer, no backoff, no new decision logic. A tap on the
  /// settings screen's "Retry" action is the only caller; nothing in this
  /// file schedules this on its own.
  Future<void> retryFailedPush() => _queuePush(force: true);

  /// The status the OBSERVABLE state machine — is a push in flight or
  /// queued, does the current signature still differ from the last
  /// server-confirmed one, did the last attempt for that difference fail —
  /// actually implies right now. Never an edge-triggered guess: computed
  /// fresh every time [_republishStatus]'s microtask runs, from whatever the
  /// live fields say at that moment (javító kör 1, F2).
  SettingsSyncStatus _computeStatus() {
    if (!_signedIn) return SettingsSyncStatus.synced;
    if (_pushInFlight || _pushPending) return SettingsSyncStatus.pending;
    if (_currentSignature() != _syncedSignature) {
      return _lastPushFailed
          ? SettingsSyncStatus.failed
          : SettingsSyncStatus.pending;
    }
    return SettingsSyncStatus.synced;
  }

  /// Deferred past the current build/listener turn (same reentrancy rule
  /// `auth_providers.dart`'s `Future.microtask` documents): the
  /// `authControllerProvider` listener that clears state on logout fires
  /// with `fireImmediately: true` from inside this very constructor, which
  /// itself runs during `settingsSyncProvider`'s own build — writing another
  /// provider's state synchronously there is exactly the reentrancy Riverpod
  /// forbids.
  ///
  /// [_computeStatus] runs INSIDE the microtask, not at the call site — by
  /// the time it fires, the fields it reads reflect whatever is true then,
  /// not a snapshot from when this was scheduled (javító kör 1, F2/S2: this
  /// is what stops an EARLIER push's own `Success` from publishing "synced"
  /// while a LATER push for a newer edit is still unconfirmed in flight).
  void _republishStatus() {
    Future.microtask(() {
      if (!_ref.mounted) return;
      _ref.read(settingsSyncStatusProvider.notifier).publish(_computeStatus());
    });
  }

  /// Serializes full-profile PUTs. A genuine edit received during an in-flight
  /// request marks the queue dirty; once that request finishes, exactly one
  /// latest snapshot follows it. Failed writes are not replayed unless such a
  /// later edit actually occurred.
  Future<void> _queuePush({bool force = false}) async {
    if (!_signedIn) return;
    _pushPending = true;
    _forcePendingPush = _forcePendingPush || force;
    if (_pushInFlight) {
      _republishStatus();
      return;
    }

    _pushInFlight = true;
    _republishStatus();
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
      _republishStatus();
    }
  }

  Future<void> _sendPatch(Map<String, Object?> patch, String signature) async {
    final authRevision = _authRevision;
    final result = await _ref.read(settingsRepositoryProvider).update(patch);
    if (!_ref.mounted || authRevision != _authRevision) return;
    switch (result) {
      case Success():
        // Only mark synced AFTER the server confirms — otherwise an offline
        // edit would be falsely recorded as synced and silently lost. Not
        // published as "synced" directly (javító kör 1, F2/S2): a later edit
        // may already have queued a NEXT push (`_pushInFlight` still true,
        // the while-loop above isn't done), and `_computeStatus` correctly
        // reports "pending" for that in that case instead of flashing
        // "All changes saved" for a moment that has already passed.
        _syncedSignature = signature;
        _lastPushFailed = false;
        _republishStatus();
      case Failure(:final error):
        _ref
            .read(appLoggerProvider)
            .warning(
              'settings.sync_push_failed',
              fields: {'code': error.code, 'retryable': error.retryable},
            );
        _lastPushFailed = true;
        // Visible, not replayed (A4): the UI can offer a user-initiated
        // retry, but nothing in this class re-attempts on its own.
        _republishStatus();
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
