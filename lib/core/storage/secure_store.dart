import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../foundation/app_failure.dart';
import '../foundation/app_result.dart';

/// Secret storage (Android Keystore / iOS Keychain) behind one core contract
/// (SDD Ch2 Kör 5 §5.4).
///
/// Every operation returns an [AppResult]: a platform problem is a
/// [StorageFailure] the caller has to handle explicitly. It is never reported
/// as success, so "the user is signed out" (`Success(null)`) and "the secure
/// store is broken" (`Failure`) can never be confused — the distinction that
/// decides whether an app should drop a session or keep it.
abstract interface class SecureStore {
  /// The stored secret, or `Success(null)` when nothing is stored.
  Future<AppResult<String?>> read(String key);

  Future<AppResult<void>> write(String key, String value);

  Future<AppResult<void>> delete(String key);
}

/// `flutter_secure_storage` implementation — the only place in `lib/` that
/// imports the plugin.
class FlutterSecureStore implements SecureStore {
  FlutterSecureStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<AppResult<String?>> read(String key) => _guard(
    () => _storage.read(key: key),
    FailureCode.storageRead,
    // No platform channel (host tests / unsupported desktop): nothing can ever
    // have been stored, so "no secret" IS the correct answer, not a guess.
    onMissingPlugin: () => null,
  );

  @override
  Future<AppResult<void>> write(String key, String value) => _guard(
    () => _storage.write(key: key, value: value),
    FailureCode.storageWrite,
  );

  @override
  Future<AppResult<void>> delete(String key) =>
      _guard(() => _storage.delete(key: key), FailureCode.storageWrite);

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
