import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_repository.dart';
import '../data/token_store.dart';
import '../model/auth_user.dart';

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
final authEventProvider =
    NotifierProvider<AuthEventController, AuthEvent?>(AuthEventController.new);

/// The session controller. State is the signed-in [AuthUser], or null when
/// logged out. Restores a persisted session on first read.
class AuthController extends AsyncNotifier<AuthUser?> {
  TokenStore get _tokens => ref.read(tokenStoreProvider);
  AuthRepository get _repo => ref.read(authRepositoryProvider);

  @override
  Future<AuthUser?> build() async {
    final token = await _tokens.read();
    if (token == null || token.isEmpty) return null;
    try {
      final user = await _repo.me();
      // Defer the event past this provider's initialization (Riverpod forbids
      // mutating another provider during build). A restored session behaves
      // like a login → the cloud profile is pulled down.
      Future.microtask(
        () => ref.read(authEventProvider.notifier).emit(AuthEvent.loggedIn),
      );
      return user;
    } catch (_) {
      // Stored token is invalid/expired — drop it and start logged out.
      await _tokens.clear();
      return null;
    }
  }

  Future<void> login(String email, String password) =>
      _authenticate(() => _repo.login(email, password), AuthEvent.loggedIn);

  Future<void> register(String email, String password) =>
      _authenticate(() => _repo.register(email, password), AuthEvent.registered);

  /// Store the token from [getToken], then load the user. Errors (e.g.
  /// [AuthException]) surface as an AsyncError the UI reads via `state.error`.
  Future<void> _authenticate(
    Future<String> Function() getToken,
    AuthEvent event,
  ) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final token = await getToken();
      await _tokens.write(token);
      return _repo.me();
    });
    if (state.value != null) {
      ref.read(authEventProvider.notifier).emit(event);
    }
  }

  Future<void> logout() async {
    await _tokens.clear();
    state = const AsyncData(null);
  }
}

final authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthUser?>(AuthController.new);

/// Convenience: true when a user is signed in (ignores loading/error).
final isSignedInProvider = Provider<bool>(
  (ref) => ref.watch(authControllerProvider).value != null,
);
