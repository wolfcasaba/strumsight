import '../../../core/foundation/app_failure.dart';
import '../../../core/foundation/app_result.dart';
import '../../../core/network/api_client.dart';
import '../model/auth_user.dart';

/// Talks to the account backend. An interface so widget/unit tests inject a
/// fake without hitting the network.
///
/// Every method returns an [AppResult]: a `DioException` never leaves this
/// file (E01-R04 §4.4), and the UI localises the [AppFailure.code].
abstract interface class AuthRepository {
  /// Register, returning a usable access token (the backend auto-logs-in).
  Future<AppResult<String>> register(String email, String password);

  /// Log in, returning an access token.
  Future<AppResult<String>> login(String email, String password);

  /// The currently authenticated user (token attached by the Dio interceptor).
  Future<AppResult<AuthUser>> me();
}

class HttpAuthRepository implements AuthRepository {
  HttpAuthRepository(this._client);

  final ApiClient _client;

  @override
  Future<AppResult<String>> register(String email, String password) =>
      _postForToken(
        '/auth/register',
        email,
        password,
        conflictCode: FailureCode.validationEmailTaken,
      );

  @override
  Future<AppResult<String>> login(String email, String password) =>
      _postForToken('/auth/login', email, password);

  Future<AppResult<String>> _postForToken(
    String path,
    String email,
    String password, {
    String conflictCode = FailureCode.validationInvalidInput,
  }) {
    return _client.postJson<String>(
      path,
      data: {'email': email, 'password': password},
      requiresAuthentication: false,
      unauthorizedCode: FailureCode.authInvalidCredentials,
      conflictCode: conflictCode,
      decode: (json) {
        final token = json['access_token'];
        if (token is! String || token.isEmpty) {
          throw const FormatException('Missing access token.');
        }
        return token;
      },
    );
  }

  @override
  Future<AppResult<AuthUser>> me() =>
      _client.getJson('/auth/me', decode: AuthUser.fromJson);
}

/// Safe fallback for disabled-account builds and impossible deep links.
final class DisabledAuthRepository implements AuthRepository {
  const DisabledAuthRepository();

  static const Failure<Never> _disabled = Failure(ConfigurationFailure());

  @override
  Future<AppResult<String>> login(String email, String password) async =>
      _disabled;

  @override
  Future<AppResult<AuthUser>> me() async => _disabled;

  @override
  Future<AppResult<String>> register(String email, String password) async =>
      _disabled;
}
