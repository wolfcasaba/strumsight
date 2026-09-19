import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/logger_provider.dart';
import '../../../core/storage/json_document_store.dart';
import '../../../core/storage/storage_keys.dart';
import '../../../core/storage/storage_providers.dart';
import '../model/strum_challenge_best.dart';

/// Today's challenge best, persisted locally as a single versioned document
/// (the streak's pattern, Kör 7 §7.2). Not a collection — there is exactly
/// one "today".
abstract interface class StrumChallengeBestRepository {
  /// The stored record, or null when there is none (or the stored one could
  /// not be decoded — the caller starts the day fresh and the corrupt bytes
  /// stay quarantined, never silently rewritten).
  StrumChallengeBest? load();

  Future<void> save(StrumChallengeBest best);
}

class KeyValueStrumChallengeBestRepository
    implements StrumChallengeBestRepository {
  const KeyValueStrumChallengeBestRepository(this._best);

  final JsonObjectStore<StrumChallengeBest> _best;

  @override
  StrumChallengeBest? load() => _best.read();

  @override
  Future<void> save(StrumChallengeBest best) => _best.write(best);
}

final strumChallengeBestRepositoryProvider =
    Provider<StrumChallengeBestRepository>((ref) {
      return KeyValueStrumChallengeBestRepository(
        JsonObjectStore<StrumChallengeBest>(
          document: JsonDocumentStore(
            store: ref.watch(keyValueStoreProvider),
            logger: ref.watch(appLoggerProvider),
            key: StorageKeys.strumChallengeBest,
            // A brand-new key: no shipped build ever wrote a pre-envelope
            // blob for it, so there is nothing legacy to read.
            legacyKey: '',
            name: 'strum_challenge',
            bodyKey: 'data',
          ),
          fromJson: StrumChallengeBest.fromJson,
          toJson: (best) => best.toJson(),
        ),
      );
    });
