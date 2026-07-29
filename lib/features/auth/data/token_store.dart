import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/foundation/app_failure.dart';
import '../../../core/foundation/app_result.dart';

/// Persists the JWT in the platform secure store (Android Keystore / iOS
/// Keychain). Abstracted so tests can substitute an in-memory implementation.
///
/// Every operation returns an [AppResult]: a storage problem is reported to the
/// caller, which then makes an explicit, documented decision (E01-R04 §4.5) —
/// it is never silently treated as success.
abstract interface class TokenStore {
  /// The stored token, or `Success(null)` when there is none.
  Future<AppResult<String?>> read();

  Future<AppResult<void>> write(String token);

  Future<AppResult<void>> clear();
}

class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'strumsight_auth_token';
  final FlutterSecureStorage _storage;

  @override
  Future<AppResult<String?>> read() => _guard(
    () => _storage.read(key: _key),
    FailureCode.storageRead,
    // No platform channel (host tests / unsupported desktop): there cannot be
    // a stored token, so "no token" IS the correct answer, not a guess.
    onMissingPlugin: () => null,
  );

  @override
  Future<AppResult<void>> write(String token) => _guard(
    () => _storage.write(key: _key, value: token),
    FailureCode.storageWrite,
  );

  @override
  Future<AppResult<void>> clear() =>
      _guard(() => _storage.delete(key: _key), FailureCode.storageWrite);

  /// Runs [action], converting the two failure modes we can distinguish into
  /// values. A missing platform channel is only reported as success when
  /// [onMissingPlugin] supplies a genuinely correct answer for that case;
  /// otherwise it is a [StorageFailure] like any other.
  Future<AppResult<T>> _guard<T>(
    Future<T> Function() action,
    String code, {
    T Function()? onMissingPlugin,
  }) async {
    try {
      return Success(await action());
    } on MissingPluginException catch (e, stackTrace) {
      if (onMissingPlugin != null) return Success(onMissingPlugin());
      return Failure(
        StorageFailure(
          code: FailureCode.storageUnavailable,
          cause: e,
          stackTrace: stackTrace,
        ),
      );
    } catch (e, stackTrace) {
      return Failure(
        StorageFailure(code: code, cause: e, stackTrace: stackTrace),
      );
    }
  }
}

final tokenStoreProvider = Provider<TokenStore>((ref) => SecureTokenStore());
