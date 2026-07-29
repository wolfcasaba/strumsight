import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/config/app_config.dart';
import '../../../core/foundation/app_failure.dart';
import '../../../core/foundation/app_result.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/logging/logger_provider.dart';
import '../data/auth_repository.dart';
import '../data/token_store.dart';
import '../model/auth_user.dart';

/// Whether the account layer (login + sync UI) is shown. Follows the
/// bootstrap-validated [AppConfig] (E01-R03); overridable in tests.
final accountEnabledProvider = Provider<bool>(
  (ref) => ref.watch(appConfigProvider).flags.accountEnabled,
);

/// How a session began — lets the settings-sync layer tell a fresh signup
/// (adopt this device's local settings as the new cloud profile) apart from a
/// login/restore (the cloud profile is the source of truth → pull it down).
enum AuthEvent { loggedIn, registered }

class AuthEventController extends Notifier<AuthEvent?> {
  @override
  AuthEvent? build() => null;

  void emit(AuthEvent event) => state = event;
}

/// Fires on each successful authentication (login/restore/register). Null until
/// the first event.
final authEventProvider = NotifierProvider<AuthEventController, AuthEvent?>(
  AuthEventController.new,
);

/// The session controller. State is the signed-in [AuthUser], or null when
/// logged out. Restores a persisted session on first read.
class AuthController extends AsyncNotifier<AuthUser?> {
  TokenStore get _tokens => ref.read(tokenStoreProvider);
  AuthRepository get _repo => ref.read(authRepositoryProvider);
  AppLogger get _log => ref.read(appLoggerProvider);

  @override
  Future<AuthUser?> build() async {
    final stored = await _tokens.read();
    if (stored case Failure(:final error)) {
      // Can't reach the secure store — start logged out, but say so.
      _log.warning('auth.token_read_failed', fields: {'code': error.code});
      return null;
    }
    final token = stored.valueOrNull;
    if (token == null || token.isEmpty) return null;

    final me = await _repo.me();
    switch (me) {
      case Success(:final value):
        // Defer the event past this provider's initialization (Riverpod forbids
        // mutating another provider during build). A restored session behaves
        // like a login → the cloud profile is pulled down.
        Future.microtask(
          () => ref.read(authEventProvider.notifier).emit(AuthEvent.loggedIn),
        );
        return value;
      case Failure(:final error):
        // Only an authentication verdict proves the token is dead. A network
        // failure at launch (offline) must NOT throw the session away —
        // otherwise starting the app on a plane logs the user out for good.
        if (error is AuthenticationFailure) {
          _log.info('auth.stored_token_rejected', fields: {'code': error.code});
          await _clearToken();
        } else {
          _log.warning(
            'auth.session_restore_deferred',
            fields: {'code': error.code, 'retryable': error.retryable},
          );
        }
        return null;
    }
  }

  Future<void> login(String email, String password) =>
      _authenticate(() => _repo.login(email, password), AuthEvent.loggedIn);

  Future<void> register(String email, String password) => _authenticate(
    () => _repo.register(email, password),
    AuthEvent.registered,
  );

  /// Store the token from [getToken], then load the user. A failure lands in
  /// `state.error` as an [AppFailure] — the UI localises `error.code`; no
  /// transport type (DioException) ever reaches it.
  Future<void> _authenticate(
    Future<AppResult<String>> Function() getToken,
    AuthEvent event,
  ) async {
    state = const AsyncLoading();

    final tokenResult = await getToken();
    if (tokenResult case Failure(:final error)) {
      _fail(error, 'auth.sign_in_failed');
      return;
    }

    // A secure-store write failure is NOT fatal: this run stays signed in, the
    // session just won't survive a restart. Explicit, logged decision (§4.5).
    final written = await _tokens.write(tokenResult.valueOrNull!);
    if (written case Failure(:final error)) {
      _log.warning('auth.token_write_failed', fields: {'code': error.code});
    }

    final me = await _repo.me();
    switch (me) {
      case Success(:final value):
        state = AsyncData(value);
        ref.read(authEventProvider.notifier).emit(event);
      case Failure(:final error):
        // We hold a token we cannot use — drop it so the next launch starts
        // clean instead of retrying a broken session.
        await _clearToken();
        _fail(error, 'auth.profile_load_failed');
    }
  }

  void _fail(AppFailure failure, String event) {
    _log.warning(event, fields: {'code': failure.code});
    state = AsyncError(failure, failure.stackTrace ?? StackTrace.current);
  }

  /// Best-effort token removal. A failure here is logged, never swallowed —
  /// the app still returns to the logged-out state, which is the safe side.
  Future<void> _clearToken() async {
    final cleared = await _tokens.clear();
    if (cleared case Failure(:final error)) {
      _log.warning('auth.token_clear_failed', fields: {'code': error.code});
    }
  }

  Future<void> logout() async {
    await _clearToken();
    state = const AsyncData(null);
  }
}

final authControllerProvider = AsyncNotifierProvider<AuthController, AuthUser?>(
  AuthController.new,
);

/// Convenience: true when a user is signed in (ignores loading/error).
final isSignedInProvider = Provider<bool>(
  (ref) => ref.watch(authControllerProvider).value != null,
);
