import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/auth/data/token_store.dart';

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
  test('round-trips a token through the secure store', () async {
    final store = SecureTokenStore(_MemoryStorage());

    expect((await store.read()).valueOrNull, isNull);
    expect(await store.write('jwt-1'), isA<Success<void>>());
    expect((await store.read()).valueOrNull, 'jwt-1');
    expect(await store.clear(), isA<Success<void>>());
    expect((await store.read()).valueOrNull, isNull);
  });

  test('a platform error becomes a StorageFailure, not an exception', () async {
    final store = SecureTokenStore(
      _FailingStorage(PlatformException(code: 'keystore')),
    );

    final read = await store.read();
    expect(read, isA<Failure<String?>>());
    expect(read.failureOrNull, isA<StorageFailure>());
    expect(read.failureOrNull!.code, FailureCode.storageRead);

    expect(
      (await store.write('jwt')).failureOrNull!.code,
      FailureCode.storageWrite,
    );
    expect((await store.clear()).failureOrNull!.code, FailureCode.storageWrite);
  });

  test('no platform channel: read is "no token", writes still fail', () async {
    // A missing channel means there IS no stored token — that is a correct
    // answer for read. It is NOT a licence to report a write as successful.
    final store = SecureTokenStore(
      _FailingStorage(MissingPluginException('no channel')),
    );

    final read = await store.read();
    expect(read, isA<Success<String?>>());
    expect(read.valueOrNull, isNull);

    final write = await store.write('jwt');
    expect(write, isA<Failure<void>>());
    expect(write.failureOrNull!.code, FailureCode.storageUnavailable);
  });
}
