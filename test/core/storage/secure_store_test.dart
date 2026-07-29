import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/storage/secure_store.dart';

// E01-R05 §5.4 — the secure store must never turn a platform failure into a
// success: "signed out" (Success(null)) and "the keystore is broken" (Failure)
// have to stay distinguishable, or a transient error silently drops a session.
// (Moved here from the auth feature in R05: the platform mapping is core's.)

const _key = 'test.secret';

/// Secure storage that fails the way the platform can: either with no channel
/// at all (host tests / unsupported desktop) or with a real platform error.
class _FailingStorage extends FlutterSecureStorage {
  const _FailingStorage(this.error);

  final Object error;

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => throw error;

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => throw error;

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => throw error;
}

/// A working in-memory secure storage.
class _MemoryStorage extends FlutterSecureStorage {
  _MemoryStorage();

  final Map<String, String> values = {};

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values.remove(key);
}

void main() {
  test('round-trips a secret', () async {
    final store = FlutterSecureStore(_MemoryStorage());

    expect((await store.read(_key)).valueOrNull, isNull);
    expect(await store.write(_key, 'jwt-1'), isA<Success<void>>());
    expect((await store.read(_key)).valueOrNull, 'jwt-1');
    expect(await store.delete(_key), isA<Success<void>>());
    expect((await store.read(_key)).valueOrNull, isNull);
  });

  test('keys are independent', () async {
    final store = FlutterSecureStore(_MemoryStorage());
    await store.write('a', '1');
    await store.write('b', '2');
    expect((await store.read('a')).valueOrNull, '1');
    expect((await store.read('b')).valueOrNull, '2');
  });

  test('a platform error becomes a StorageFailure, not an exception', () async {
    final store = FlutterSecureStore(
      _FailingStorage(PlatformException(code: 'keystore')),
    );

    final read = await store.read(_key);
    expect(read, isA<Failure<String?>>());
    expect(read.failureOrNull, isA<StorageFailure>());
    expect(read.failureOrNull!.code, FailureCode.storageRead);

    expect(
      (await store.write(_key, 'jwt')).failureOrNull!.code,
      FailureCode.storageWrite,
    );
    expect(
      (await store.delete(_key)).failureOrNull!.code,
      FailureCode.storageWrite,
    );
  });

  test('no platform channel: read is "no secret", writes still fail', () async {
    // A missing channel means there IS no stored secret — that is a correct
    // answer for read. It is NOT a licence to report a write as successful.
    final store = FlutterSecureStore(
      _FailingStorage(MissingPluginException('no channel')),
    );

    final read = await store.read(_key);
    expect(read, isA<Success<String?>>());
    expect(read.valueOrNull, isNull);

    final write = await store.write(_key, 'jwt');
    expect(write, isA<Failure<void>>());
    expect(write.failureOrNull!.code, FailureCode.storageUnavailable);

    final delete = await store.delete(_key);
    expect(delete, isA<Failure<void>>());
    expect(delete.failureOrNull!.code, FailureCode.storageUnavailable);
  });
}
