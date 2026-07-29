import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/auth/data/auth_repository.dart';
import 'package:strumsight/features/auth/data/token_store.dart';
import 'package:strumsight/features/auth/model/auth_user.dart';

/// In-memory token store for tests (no platform channel).
///
/// Set the `*Failure` fields to simulate a secure-storage outage.
class FakeTokenStore implements TokenStore {
  FakeTokenStore([this.token]);

  String? token;
  int reads = 0;
  int clears = 0;
  int writes = 0;

  AppFailure? readFailure;
  AppFailure? writeFailure;
  AppFailure? clearFailure;

  @override
  Future<AppResult<String?>> read() async {
    reads++;
    return readFailure != null ? Failure(readFailure!) : Success(token);
  }

  @override
  Future<AppResult<void>> write(String token) async {
    writes++;
    if (writeFailure != null) return Failure(writeFailure!);
    this.token = token;
    return const Success(null);
  }

  @override
  Future<AppResult<void>> clear() async {
    clears++;
    if (clearFailure != null) return Failure(clearFailure!);
    token = null;
    return const Success(null);
  }
}

/// Scriptable auth backend for tests. Set the `*Failure` fields to make a call
/// fail; otherwise it succeeds and `me()` returns [user].
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({
    this.user = const AuthUser(id: 1, email: 'player@strumsight.app'),
  });

  AuthUser user;
  AppFailure? loginFailure;
  AppFailure? registerFailure;
  AppFailure? meFailure;

  int loginCalls = 0;
  int registerCalls = 0;
  int meCalls = 0;

  @override
  Future<AppResult<String>> login(String email, String password) async {
    loginCalls++;
    if (loginFailure != null) return Failure(loginFailure!);
    return const Success('fake-token');
  }

  @override
  Future<AppResult<String>> register(String email, String password) async {
    registerCalls++;
    if (registerFailure != null) return Failure(registerFailure!);
    return const Success('fake-token');
  }

  @override
  Future<AppResult<AuthUser>> me() async {
    meCalls++;
    return meFailure != null ? Failure(meFailure!) : Success(user);
  }
}

/// Captures what was logged so a test can assert both what IS and what is NOT
/// in the log (no token, no password, no e-mail).
class RecordingLogSink {
  final List<String> lines = <String>[];

  void call(String line) => lines.add(line);

  String get joined => lines.join('\n');
}
