import 'package:music_theory/features/auth/data/auth_repository.dart';
import 'package:music_theory/features/auth/data/token_store.dart';
import 'package:music_theory/features/auth/model/auth_user.dart';

/// In-memory token store for tests (no platform channel).
class FakeTokenStore implements TokenStore {
  FakeTokenStore([this.token]);

  String? token;
  int clears = 0;

  @override
  Future<String?> read() async => token;

  @override
  Future<void> write(String token) async => this.token = token;

  @override
  Future<void> clear() async {
    clears++;
    token = null;
  }
}

/// Scriptable auth backend for tests. Set the `*Error` fields to make a call
/// throw; otherwise it succeeds and `me()` returns [user].
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({
    this.user = const AuthUser(id: 1, email: 'player@strumsight.app'),
  });

  AuthUser user;
  AuthException? loginError;
  AuthException? registerError;
  AuthException? meError;

  int loginCalls = 0;
  int registerCalls = 0;

  @override
  Future<String> login(String email, String password) async {
    loginCalls++;
    if (loginError != null) throw loginError!;
    return 'fake-token';
  }

  @override
  Future<String> register(String email, String password) async {
    registerCalls++;
    if (registerError != null) throw registerError!;
    return 'fake-token';
  }

  @override
  Future<AuthUser> me() async {
    if (meError != null) throw meError!;
    return user;
  }
}
