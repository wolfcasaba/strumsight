import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the JWT in the platform secure store (Android Keystore / iOS
/// Keychain). Abstracted so tests can substitute an in-memory implementation.
abstract interface class TokenStore {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> clear();
}

class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'strumsight_auth_token';
  final FlutterSecureStorage _storage;

  // The secure-storage platform channel is absent in tests / on unsupported
  // hosts. Degrade to "logged out" rather than crashing (mirrors MicCapture).
  @override
  Future<String?> read() async {
    try {
      return await _storage.read(key: _key);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String token) async {
    try {
      await _storage.write(key: _key, value: token);
    } catch (_) {
      // Best-effort; the session still works for this run.
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _storage.delete(key: _key);
    } catch (_) {
      // Best-effort.
    }
  }
}

final tokenStoreProvider = Provider<TokenStore>((ref) => SecureTokenStore());
