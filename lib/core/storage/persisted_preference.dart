import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logging/logger_provider.dart';
import 'key_value_store.dart';
import 'storage_providers.dart';

/// Shared plumbing for the single-value preference notifiers (SDD Ch2 Kör 6).
///
/// Every preference in the app follows the same shape: read the current value
/// synchronously while the notifier builds, then write it back when the user
/// changes it. Both halves are one-liners here so the interesting part of each
/// provider stays its own domain rule (clamp, enum parse, allowed options).
///
/// The read is synchronous **by construction**: the store is opened during
/// bootstrap, before the first frame, and injected. That deletes the whole
/// "default now, real value later" race the old providers guarded with a
/// `_userSet` flag — there is no longer a window in which a late-landing disk
/// read can overwrite a value the user just set.
mixin PersistedPreference<T> on Notifier<T> {
  /// The store injected at boot. Never null in a correctly wired container:
  /// `keyValueStoreProvider` throws rather than fall back to a store that would
  /// silently drop writes.
  KeyValueStore get preferences => ref.read(keyValueStoreProvider);

  /// Persist a preference, reporting — never swallowing — a platform refusal.
  ///
  /// A failed write must not take the UI down: the in-memory [state] already
  /// reflects the user's choice and stays correct for this session. What it
  /// must not do is vanish, so the failure is logged with the key that could
  /// not be written.
  Future<void> persist(
    String key,
    Future<void> Function(KeyValueStore store) write,
  ) async {
    try {
      await write(preferences);
    } on StorageException catch (e, stackTrace) {
      ref
          .read(appLoggerProvider)
          .error(
            'storage.preference.write_failed',
            error: e,
            stackTrace: stackTrace,
            fields: {'preference_key': key},
          );
    }
  }
}
