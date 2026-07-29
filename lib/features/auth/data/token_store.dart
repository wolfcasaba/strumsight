import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/foundation/app_result.dart';
import '../../../core/storage/secure_store.dart';
import '../../../core/storage/storage_keys.dart';
import '../../../core/storage/storage_providers.dart';

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

/// The auth feature's view of the shared [SecureStore] (E01-R05 §5.4): it owns
/// the key, the core store owns the platform and its failure mapping.
class SecureTokenStore implements TokenStore {
  const SecureTokenStore(this._store);

  final SecureStore _store;

  @override
  Future<AppResult<String?>> read() => _store.read(StorageKeys.secureAuthToken);

  @override
  Future<AppResult<void>> write(String token) =>
      _store.write(StorageKeys.secureAuthToken, token);

  @override
  Future<AppResult<void>> clear() => _store.delete(StorageKeys.secureAuthToken);
}

final tokenStoreProvider = Provider<TokenStore>(
  (ref) => SecureTokenStore(ref.watch(secureStoreProvider)),
);
