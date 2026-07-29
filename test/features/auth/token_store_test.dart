import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/storage/secure_store.dart';
import 'package:strumsight/core/storage/storage_keys.dart';
import 'package:strumsight/features/auth/data/token_store.dart';

// E01-R05 §5.4 — the auth feature owns the KEY, the core SecureStore owns the
// platform. These tests pin that split: the right key is used, and a storage
// failure is passed through untouched (never softened into "no token", which
// would silently sign the user out).
// The platform-error mapping itself lives in test/core/storage/secure_store_test.dart.

class _FakeSecureStore implements SecureStore {
  _FakeSecureStore({this.failure});

  final AppFailure? failure;
  final Map<String, String> values = {};
  final List<String> keysTouched = [];

  @override
  Future<AppResult<String?>> read(String key) async {
    keysTouched.add(key);
    return failure == null ? Success(values[key]) : Failure(failure!);
  }

  @override
  Future<AppResult<void>> write(String key, String value) async {
    keysTouched.add(key);
    if (failure != null) return Failure(failure!);
    values[key] = value;
    return const Success(null);
  }

  @override
  Future<AppResult<void>> delete(String key) async {
    keysTouched.add(key);
    if (failure != null) return Failure(failure!);
    values.remove(key);
    return const Success(null);
  }
}

void main() {
  test('round-trips a token under the documented secure key', () async {
    final secure = _FakeSecureStore();
    final store = SecureTokenStore(secure);

    expect((await store.read()).valueOrNull, isNull);
    expect(await store.write('jwt-1'), isA<Success<void>>());
    expect(secure.values[StorageKeys.secureAuthToken], 'jwt-1');
    expect((await store.read()).valueOrNull, 'jwt-1');
    expect(await store.clear(), isA<Success<void>>());
    expect((await store.read()).valueOrNull, isNull);

    expect(secure.keysTouched, everyElement(StorageKeys.secureAuthToken));
  });

  test('a storage failure reaches the caller unchanged', () async {
    const error = StorageFailure(code: FailureCode.storageRead);
    final store = SecureTokenStore(_FakeSecureStore(failure: error));

    expect((await store.read()).failureOrNull, same(error));
    expect((await store.write('jwt')).failureOrNull, same(error));
    expect((await store.clear()).failureOrNull, same(error));
  });
}
