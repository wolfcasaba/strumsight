import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/storage/key_value_store.dart';
import 'package:strumsight/core/storage/shared_preferences_store.dart';
import 'package:strumsight/core/storage/storage_keys.dart';
import 'package:strumsight/core/storage/storage_providers.dart';

import 'in_memory_key_value_store.dart';

// E01-R05 — the KeyValueStore contract (SDD Ch2 §7.4 / Kör 5):
// primitives round-trip, remove works, an unreadable value degrades to null
// instead of throwing, and a rejected write is NEVER a silent no-op.

/// A SharedPreferences whose writes are refused by the platform (`false`), the
/// shape that used to disappear into a `try/catch`.
class _RejectingPrefs implements SharedPreferences {
  @override
  Future<bool> setString(String key, String value) async => false;

  @override
  Future<bool> remove(String key) async => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A SharedPreferences whose writes throw a platform error.
class _ThrowingPrefs implements SharedPreferences {
  @override
  Future<bool> setBool(String key, bool value) async =>
      throw PlatformException(code: 'disk-full');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// The same contract, run against the production store and the test double.
  void contractTests(String name, Future<KeyValueStore> Function() create) {
    group(name, () {
      late KeyValueStore store;
      setUp(() async => store = await create());

      test('every primitive round-trips', () async {
        await store.writeString('s', 'hello');
        await store.writeInt('i', 7);
        await store.writeDouble('d', 1.5);
        await store.writeBool('b', true);
        await store.writeStringList('l', const ['a', 'b']);

        expect(store.readString('s'), 'hello');
        expect(store.readInt('i'), 7);
        expect(store.readDouble('d'), 1.5);
        expect(store.readBool('b'), isTrue);
        expect(store.readStringList('l'), ['a', 'b']);
      });

      test('an absent key reads null and is not contained', () {
        expect(store.readString('nope'), isNull);
        expect(store.readInt('nope'), isNull);
        expect(store.readDouble('nope'), isNull);
        expect(store.readBool('nope'), isNull);
        expect(store.readStringList('nope'), isNull);
        expect(store.contains('nope'), isFalse);
      });

      test('contains reflects write then remove', () async {
        await store.writeString('k', 'v');
        expect(store.contains('k'), isTrue);
        await store.remove('k');
        expect(store.contains('k'), isFalse);
        expect(store.readString('k'), isNull);
      });

      test('remove of an absent key is a no-op, not an error', () async {
        await store.remove('never-written');
        expect(store.contains('never-written'), isFalse);
      });

      test('a value read as the wrong type degrades to null, keeping the '
          'bytes on disk for a migration', () async {
        await store.writeInt('typed', 42);
        expect(store.readString('typed'), isNull);
        expect(store.readBool('typed'), isNull);
        // Still there — the fallback did not destroy anything.
        expect(store.contains('typed'), isTrue);
        expect(store.readInt('typed'), 42);
      });

      test('overwriting replaces the value', () async {
        await store.writeInt('n', 1);
        await store.writeInt('n', 2);
        expect(store.readInt('n'), 2);
      });
    });
  }

  contractTests('SharedPreferencesStore', () async {
    SharedPreferences.setMockInitialValues({});
    final result = await SharedPreferencesStore.open();
    return (result as Success<SharedPreferencesStore>).value;
  });

  contractTests('InMemoryKeyValueStore', () async => InMemoryKeyValueStore());

  group('SharedPreferencesStore failure handling', () {
    test('a refused write throws StorageException (never a silent no-op)', () {
      final store = SharedPreferencesStore(_RejectingPrefs());
      expect(
        () => store.writeString('k', 'v'),
        throwsA(
          isA<StorageException>()
              .having((e) => e.code, 'code', FailureCode.storageWrite)
              .having((e) => e.key, 'key', 'k'),
        ),
      );
    });

    test('a refused remove throws StorageException', () {
      final store = SharedPreferencesStore(_RejectingPrefs());
      expect(() => store.remove('k'), throwsA(isA<StorageException>()));
    });

    test('a thrown platform error becomes a StorageException', () {
      final store = SharedPreferencesStore(_ThrowingPrefs());
      expect(
        () => store.writeBool('k', true),
        throwsA(
          isA<StorageException>().having(
            (e) => e.cause,
            'cause',
            isA<PlatformException>(),
          ),
        ),
      );
    });

    test('StorageException.toString never leaks the stored value', () {
      const e = StorageException(
        FailureCode.storageWrite,
        key: 'k',
        cause: 'secret-value',
      );
      expect(e.toString(), isNot(contains('secret-value')));
      expect(e.toString(), contains('storage.write'));
    });
  });

  group('storage providers', () {
    test('an un-overridden keyValueStoreProvider fails loudly', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      // Riverpod 3 wraps a provider's error in a ProviderException, so assert
      // on the message the developer actually sees.
      expect(
        () => container.read(keyValueStoreProvider),
        throwsA(
          isA<Object>().having(
            (e) => e.toString(),
            'message',
            allOf(
              contains('UnimplementedError'),
              contains('must be overridden'),
            ),
          ),
        ),
      );
    });

    test('a fake store can be injected by override', () async {
      final fake = InMemoryKeyValueStore({StorageKeys.capoFret: 3});
      final container = ProviderContainer(
        overrides: [keyValueStoreProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);

      final store = container.read(keyValueStoreProvider);
      expect(store.readInt(StorageKeys.capoFret), 3);
      await store.writeInt(StorageKeys.capoFret, 5);
      expect(fake.values[StorageKeys.capoFret], 5);
    });
  });

  group('StorageKeys catalogue', () {
    test('every key is unique and namespaced', () {
      expect(StorageKeys.all.toSet(), hasLength(StorageKeys.all.length));
      for (final key in StorageKeys.all) {
        expect(key, startsWith('ss.'), reason: '$key must be namespaced');
      }
    });

    test('the secure token key is deliberately NOT renamed — renaming it '
        'would sign every user out', () {
      expect(StorageKeys.secureAuthToken, 'strumsight_auth_token');
      expect(StorageKeys.all, isNot(contains(StorageKeys.secureAuthToken)));
    });
  });
}
