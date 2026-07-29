import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/config/app_config.dart';
import '../../../core/foundation/app_failure.dart';
import '../../../core/foundation/app_result.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/logging/logger_provider.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/dio_factory.dart';
import '../data/auth_repository.dart';
import '../data/token_store.dart';
import '../model/auth_user.dart';

/// Whether the account layer (login + sync UI) is shown. Follows the
/// bootstrap-validated [AppConfig] (E01-R03); overridable in tests.
final accountEnabledProvider = Provider<bool>(
  (ref) => ref.watch(appConfigProvider).flags.accountEnabled,
);

final accountDioFactoryProvider = Provider<DioFactory>((ref) {
  final config = ref.watch(appConfigProvider);
  return DioFactory(
    baseUrl: config.apiBaseUrl,
    appVersion: config.appVersion,
    logger: ref.watch(appLoggerProvider),
  );
});

final class _AuthSessionGeneration {
  int value = 0;

  void advance() => value++;
}

final _authSessionGenerationProvider = Provider<_AuthSessionGeneration>(
  (_) => _AuthSessionGeneration(),
);

final class _AuthSessionCredentials {
  String? accessToken;

  void clear() => accessToken = null;
}

final _authSessionCredentialsProvider = Provider<_AuthSessionCredentials>(
  (_) => _AuthSessionCredentials(),
);

/// Secure-store mutations must observe the same ordering as session changes.
///
/// The platform store is asynchronous: without this queue a slow logout clear
/// can finish after a newer login write (or a slow old write can finish after
/// logout), leaving the persisted token out of sync with the published state.
final class _AuthTokenMutationQueue {
  Future<void> _tail = Future<void>.value();

  Future<AppResult<void>> enqueue(Future<AppResult<void>> Function() mutation) {
    final result = Completer<AppResult<void>>();
    _tail = _tail.then((_) async {
      try {
        result.complete(await mutation());
      } on Object catch (error, stackTrace) {
        // TokenStore's contract is AppResult, but keep one buggy platform
        // implementation from poisoning the queue for every later mutation.
        result.complete(
          Failure(
            StorageFailure(
              code: FailureCode.storageUnavailable,
              cause: error,
              stackTrace: stackTrace,
            ),
          ),
        );
      }
    });
    return result.future;
  }
}

final _authTokenMutationQueueProvider = Provider<_AuthTokenMutationQueue>(
  (_) => _AuthTokenMutationQueue(),
);

/// Lazily creates the account transport only for account-enabled builds.
final accountApiClientProvider = Provider<ApiClient?>((ref) {
  final config = ref.watch(appConfigProvider);
  if (!config.flags.accountEnabled) return null;

  final generation = ref.watch(_authSessionGenerationProvider);
  final credentials = ref.watch(_authSessionCredentialsProvider);
  final client = ref
      .watch(accountDioFactoryProvider)
      .createAccountClient(
        accountEnabled: true,
        readToken: () async => Success(credentials.accessToken),
        readSessionGeneration: () => generation.value,
        // Use an event-queue turn, not the interceptor's request stack. During
        // session restore `/auth/me` is itself awaited by AuthController.build;
        // mutating that provider inline would be Riverpod reentrancy.
        onUnauthorized: (rejectedGeneration) {
          Timer.run(() {
            if (!ref.mounted) return;
            if (generation.value != rejectedGeneration) return;
            unawaited(
              ref.read(authControllerProvider.notifier).invalidateSession(),
            );
          });
        },
      );
  ref.onDispose(client.close);
  return client;
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final client = ref.watch(accountApiClientProvider);
  return client == null
      ? const DisabledAuthRepository()
      : HttpAuthRepository(client);
});

/// How a session began — lets the settings-sync layer tell a fresh signup
/// (adopt this device's local settings as the new cloud profile) apart from a
/// login/restore (the cloud profile is the source of truth → pull it down).
enum AuthEvent { loggedIn, registered }

class AuthEventController extends Notifier<AuthEvent?> {
  @override
  AuthEvent? build() => null;

  void emit(AuthEvent event) {
    // This provider carries events, not durable state. Re-emitting the same
    // enum after a logout/login must still notify settings synchronization.
    if (state == event) state = null;
    state = event;
  }

  void clear() => state = null;
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
  _AuthSessionGeneration get _sessionGeneration =>
      ref.read(_authSessionGenerationProvider);
  _AuthSessionCredentials get _sessionCredentials =>
      ref.read(_authSessionCredentialsProvider);
  _AuthTokenMutationQueue get _tokenMutations =>
      ref.read(_authTokenMutationQueueProvider);

  @override
  Future<AuthUser?> build() async {
    // Do not even read a stale secure token in an account-disabled build:
    // doing so used to let the root settings listener restore `/auth/me`.
    if (!ref.watch(accountEnabledProvider)) return null;
    final operationGeneration = _startOperation();
    _sessionCredentials.clear();

    final stored = await _tokens.read();
    if (!_isCurrentOperation(operationGeneration)) return _staleBuildValue();
    if (stored case Failure(:final error)) {
      // Can't reach the secure store — start logged out, but say so.
      _log.warning('auth.token_read_failed', fields: {'code': error.code});
      return null;
    }
    final token = stored.valueOrNull;
    if (token == null || token.isEmpty) return null;
    _sessionCredentials.accessToken = token;

    final me = await _repo.me();
    if (!_isCurrentOperation(operationGeneration)) return _staleBuildValue();
    switch (me) {
      case Success(:final value):
        // Defer the event past this provider's initialization (Riverpod forbids
        // mutating another provider during build). A restored session behaves
        // like a login → the cloud profile is pulled down.
        Future.microtask(() {
          if (!_isCurrentOperation(operationGeneration)) return;
          ref.read(authEventProvider.notifier).emit(AuthEvent.loggedIn);
        });
        return value;
      case Failure(:final error):
        _sessionCredentials.clear();
        // Only an authentication verdict proves the token is dead. A network
        // failure at launch (offline) must NOT throw the session away —
        // otherwise starting the app on a plane logs the user out for good.
        if (error is AuthenticationFailure) {
          _log.info('auth.stored_token_rejected', fields: {'code': error.code});
          await _clearToken();
          if (!_isCurrentOperation(operationGeneration)) {
            return _staleBuildValue();
          }
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
    ref.read(authEventProvider.notifier).clear();
    final operationGeneration = _startOperation();
    _sessionCredentials.clear();
    state = const AsyncLoading();

    final tokenResult = await getToken();
    if (!_isCurrentOperation(operationGeneration)) return;
    if (tokenResult case Failure(:final error)) {
      _fail(error, 'auth.sign_in_failed');
      return;
    }

    final token = tokenResult.valueOrNull!;
    _sessionCredentials.accessToken = token;
    // A secure-store write failure is NOT fatal: this run stays signed in, the
    // session just won't survive a restart. Explicit, logged decision (§4.5).
    final written = await _writeToken(token);
    if (!_isCurrentOperation(operationGeneration)) return;
    if (written case Failure(:final error)) {
      _log.warning('auth.token_write_failed', fields: {'code': error.code});
    }

    final me = await _repo.me();
    if (!_isCurrentOperation(operationGeneration)) return;
    switch (me) {
      case Success(:final value):
        state = AsyncData(value);
        ref.read(authEventProvider.notifier).emit(event);
      case Failure(:final error):
        _sessionCredentials.clear();
        // We hold a token we cannot use — drop it so the next launch starts
        // clean instead of retrying a broken session.
        await _clearToken();
        if (!_isCurrentOperation(operationGeneration)) return;
        _fail(error, 'auth.profile_load_failed');
    }
  }

  int _startOperation() {
    _sessionGeneration.advance();
    return _sessionGeneration.value;
  }

  bool _isCurrentOperation(int generation) =>
      ref.mounted && _sessionGeneration.value == generation;

  AuthUser? _staleBuildValue() => ref.mounted ? state.value : null;

  void _fail(AppFailure failure, String event) {
    _log.warning(event, fields: {'code': failure.code});
    state = AsyncError(failure, failure.stackTrace ?? StackTrace.current);
  }

  /// Best-effort token removal. A failure here is logged, never swallowed —
  /// the app still returns to the logged-out state, which is the safe side.
  Future<void> _clearToken() async {
    final store = _tokens;
    final logger = _log;
    final cleared = await _tokenMutations.enqueue(store.clear);
    if (cleared case Failure(:final error)) {
      logger.warning('auth.token_clear_failed', fields: {'code': error.code});
    }
  }

  Future<AppResult<void>> _writeToken(String token) {
    final store = _tokens;
    return _tokenMutations.enqueue(() => store.write(token));
  }

  void _publishLoggedOut() {
    _startOperation();
    _sessionCredentials.clear();
    state = const AsyncData(null);
    ref.read(authEventProvider.notifier).clear();
  }

  Future<void> _publishLoggedOutAndClearToken() async {
    _publishLoggedOut();
    await _clearToken();
  }

  Future<void> logout() => _publishLoggedOutAndClearToken();

  /// Expires a fully established session after an authenticated request's 401.
  ///
  /// During initial restore or sign-in, state has no user yet; those call
  /// paths already process the repository failure and clear unusable tokens.
  Future<void> invalidateSession() async {
    if (state.value == null) return;
    _log.info(
      'auth.session_expired',
      fields: const {'code': FailureCode.authSessionExpired},
    );
    // Publish the safe state before the asynchronous secure-store operation.
    // This makes concurrent 401 handlers idempotent instead of clearing twice.
    await _publishLoggedOutAndClearToken();
  }
}

final authControllerProvider = AsyncNotifierProvider<AuthController, AuthUser?>(
  AuthController.new,
);

/// Convenience: true when a user is signed in (ignores loading/error).
final isSignedInProvider = Provider<bool>(
  (ref) => ref.watch(authControllerProvider).value != null,
);
