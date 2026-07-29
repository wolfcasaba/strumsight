import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'key_value_store.dart';
import 'secure_store.dart';

/// The app-wide preference store.
///
/// Deliberately has **no default**: `main` overrides it with the instance
/// bootstrap opened, and tests override it with a fake. A silent in-memory
/// fallback would look like a working app while dropping every write — the
/// exact silent-data-loss shape this layer exists to prevent, so a missing
/// override fails loudly instead.
final keyValueStoreProvider = Provider<KeyValueStore>((ref) {
  throw UnimplementedError(
    'keyValueStoreProvider must be overridden — main() injects the store '
    'opened by AppBootstrap; tests inject InMemoryKeyValueStore.',
  );
});

/// Secret storage. Safe to construct lazily: it holds no state, and every
/// operation reports platform problems as a `StorageFailure`.
final secureStoreProvider = Provider<SecureStore>(
  (ref) => FlutterSecureStore(),
);
