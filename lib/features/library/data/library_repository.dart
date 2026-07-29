import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/logger_provider.dart';
import '../../../core/storage/json_document_store.dart';
import '../../../core/storage/storage_keys.dart';
import '../../../core/storage/storage_providers.dart';
import '../model/analyzed_session.dart';

/// Persists analyzed sessions locally (offline).
///
/// An interface so the controller can be tested against an in-memory fake and
/// so the storage mechanism stays replaceable (Kör 7 §7.2: a provider never
/// serializes JSON itself).
abstract interface class LibraryRepository {
  Future<List<AnalyzedSession>> load();
  Future<void> save(List<AnalyzedSession> sessions);

  /// Documented storage bound (§7.5): the newest [maxSessions] saved analyses
  /// are kept, older ones evicted. An analysis carries a whole chord/strum
  /// timeline, so this is the heaviest user-content document — which is why it
  /// is bounded at all.
  static const int maxSessions = 100;
}

/// The shipping implementation: one versioned JSON document in the injected
/// `KeyValueStore`. One corrupt session is skipped; the rest of the library
/// still loads (§7.4).
class KeyValueLibraryRepository implements LibraryRepository {
  const KeyValueLibraryRepository(this._sessions);

  final JsonCollectionStore<AnalyzedSession> _sessions;

  @override
  Future<List<AnalyzedSession>> load() async => _sessions.read();

  @override
  Future<void> save(List<AnalyzedSession> sessions) =>
      _sessions.write(sessions);
}

final libraryRepositoryProvider = Provider<LibraryRepository>((ref) {
  return KeyValueLibraryRepository(
    JsonCollectionStore<AnalyzedSession>(
      document: JsonDocumentStore(
        store: ref.watch(keyValueStoreProvider),
        logger: ref.watch(appLoggerProvider),
        key: StorageKeys.librarySessions,
        legacyKey: LegacyStorageKeys.librarySessions,
        name: 'library',
      ),
      fromJson: AnalyzedSession.fromJson,
      toJson: (s) => s.toJson(),
      maxItems: LibraryRepository.maxSessions,
    ),
  );
});
