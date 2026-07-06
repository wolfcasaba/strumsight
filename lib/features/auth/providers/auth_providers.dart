import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_repository.dart';
import '../data/token_store.dart';
import '../model/auth_user.dart';

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
      return await _repo.me();
    } catch (_) {
      // Stored token is invalid/expired — drop it and start logged out.
      await _tokens.clear();
      return null;
    }
  }

  Future<void> login(String email, String password) =>
      _authenticate(() => _repo.login(email, password));

  Future<void> register(String email, String password) =>
      _authenticate(() => _repo.register(email, password));

  /// Store the token from [getToken], then load the user. Errors (e.g.
  /// [AuthException]) surface as an AsyncError the UI reads via `state.error`.
  Future<void> _authenticate(Future<String> Function() getToken) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final token = await getToken();
      await _tokens.write(token);
      return _repo.me();
    });
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
