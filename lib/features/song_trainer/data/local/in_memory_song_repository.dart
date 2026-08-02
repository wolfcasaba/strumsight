/// In-memory implementation of [SongRepository] used by UI tests,
/// widget previews and the diagnostics surface that want to render
/// the Library listview without an actual filesystem mount
/// (E03-R07, ADR 0090 §Döntés 1 + §Döntés 2).
///
/// The fake is faithful to the contract:
///
///   * `revision` is enforced on every `update` — stale revisions
///     produce [SongRepositoryErrorCode.staleRevision];
///   * `create` refuses duplicates with [SongRepositoryErrorCode.alreadyExists];
///   * `moveToTrash` / `restore` / `permanentlyDelete` follow the
///     documented flow (no per-document file IO happens, but the
///     state-machine is identical to the file implementation);
///   * the same [SongSummary] shape the file repository produces is
///     produced here — wire-incompatible bug fixes land once.
///
/// The fake does NOT simulate persistence; tests that want crash
/// semantics use the file repository against a temporary directory.
library;

import 'dart:async';
import 'dart:convert' show jsonEncode, utf8;

// ignore: depend_on_referenced_packages
import 'package:crypto/crypto.dart' as crypto;

import '../../../../core/foundation/app_result.dart';
import '../../domain/models/song_capability.dart';
import '../../domain/models/song_document.dart';
import '../../domain/models/song_id.dart';
import '../../domain/repositories/song_repository.dart';
import '../../domain/services/song_capability_resolver.dart';
import '../../domain/services/song_validator.dart';

/// In-memory implementation of [SongRepository]. Stores documents in a
/// `Map<SongId, SongDocument>` and tracks the trash state in a side
/// map so the summary reflects the live state of the trash query.
final class InMemorySongRepository implements SongRepository {
  /// Construct an empty in-memory repository. [clock] lets tests
  /// pin the summary's `updatedAt` deterministically. The fake shares
  /// the production validator and capability resolver so the contract
  /// ("the implementation re-runs the validator before writing",
  /// [SongRepository.create] doc) is honoured end-to-end.
  InMemorySongRepository({
    DateTime Function()? clock,
    SongValidator? validator,
    SongCapabilityResolver? capabilityResolver,
  }) : _clock = clock ?? DateTime.now,
       _documents = <SongId, SongDocument>{},
       _trashed = <SongId>{},
       _hashes = <SongId, String>{},
       _validator = validator ?? const SongValidator(),
       _capabilityResolver =
           capabilityResolver ?? const SongCapabilityResolver();

  // ignore: unused_field
  final DateTime Function() _clock;
  final Map<SongId, SongDocument> _documents;
  final Set<SongId> _trashed;
  final Map<SongId, String> _hashes;
  final SongValidator _validator;
  final SongCapabilityResolver _capabilityResolver;

  @override
  Future<AppResult<List<SongSummary>>> list(SongQuery query) async {
    final all =
        _documents.entries
            .map((entry) {
              final document = entry.value;
              final updatedAt = document.updatedAt.toUtc();
              return SongSummary(
                documentId: entry.key,
                title: document.metadata.title,
                artist: document.metadata.artist,
                tags: List<String>.unmodifiable(document.metadata.tags),
                updatedAt: updatedAt,
                lastPracticedAt: updatedAt,
                capability: null,
                sourceType: document.source.type,
                favorite: false,
                archived: false,
                trashed: _trashed.contains(entry.key),
                revision: document.revision,
                documentHash: _hashes[entry.key] ?? '0' * 64,
              );
            })
            .where((entry) {
              if (!query.includeTrashed && entry.trashed) return false;
              if (!query.includeArchived && entry.archived) return false;
              if (query.sourceTypeFilter != null &&
                  entry.sourceType != query.sourceTypeFilter) {
                return false;
              }
              if (query.titleContains != null &&
                  query.titleContains!.isNotEmpty &&
                  !entry.title.toLowerCase().contains(
                    query.titleContains!.toLowerCase(),
                  )) {
                return false;
              }
              if (query.tagFilter != null && query.tagFilter!.isNotEmpty) {
                final wanted = query.tagFilter!.toSet();
                if (!entry.tags.any(wanted.contains)) return false;
              }
              return true;
            })
            .toList()
          ..sort((a, b) => b.updatedAt.toUtc().compareTo(a.updatedAt.toUtc()));
    return AppResult<List<SongSummary>>.success(
      List<SongSummary>.unmodifiable(all),
    );
  }

  @override
  Future<AppResult<SongDocument?>> get(SongId id) async {
    final document = _documents[id];
    return AppResult<SongDocument?>.success(document);
  }

  @override
  Future<AppResult<void>> create(SongDocument document) async {
    // Step 1 (ADR 0090 §3 / ADR 0114 §Döntés 2): refuse any fatal
    // validation issue BEFORE persisting — same gate as the file
    // repository.
    final capability = _capabilityResolver.resolve(
      report: _validator.validate(document),
      profile: SongCapabilityProfile.persist,
    );
    if (!capability.canPersist) {
      return songRepositoryFailure<void>(
        SongRepositoryErrorCode.notPersistable,
      );
    }
    if (_documents.containsKey(document.id)) {
      return songRepositoryFailure<void>(SongRepositoryErrorCode.alreadyExists);
    }
    _documents[document.id] = document;
    _hashes[document.id] = _documentHash(document);
    return AppResult<void>.success(null);
  }

  @override
  Future<AppResult<void>> update(
    SongDocument document, {
    required int expectedRevision,
  }) async {
    final existing = _documents[document.id];
    if (existing == null) {
      return songRepositoryFailure<void>(SongRepositoryErrorCode.notFound);
    }
    if (existing.revision != expectedRevision) {
      return songRepositoryFailure<void>(SongRepositoryErrorCode.staleRevision);
    }
    final bumped = _copyWithRevision(document, existing.revision + 1);
    // Step 1 (ADR 0090 §3 / ADR 0114 §Döntés 2): refuse any fatal
    // validation issue BEFORE bumping the persisted revision.
    final capability = _capabilityResolver.resolve(
      report: _validator.validate(bumped),
      profile: SongCapabilityProfile.persist,
    );
    if (!capability.canPersist) {
      return songRepositoryFailure<void>(
        SongRepositoryErrorCode.notPersistable,
      );
    }
    _documents[document.id] = bumped;
    _hashes[document.id] = _documentHash(bumped);
    return AppResult<void>.success(null);
  }

  @override
  Future<AppResult<void>> moveToTrash(SongId id) async {
    if (!_documents.containsKey(id)) {
      if (_trashed.contains(id)) return AppResult<void>.success(null);
      return songRepositoryFailure<void>(SongRepositoryErrorCode.notFound);
    }
    _trashed.add(id);
    return AppResult<void>.success(null);
  }

  @override
  Future<AppResult<void>> restore(SongId id) async {
    if (_documents.containsKey(id)) {
      // Already not trashed — idempotent.
      return AppResult<void>.success(null);
    }
    if (_trashed.contains(id)) {
      return songRepositoryFailure<void>(SongRepositoryErrorCode.notFound);
    }
    return songRepositoryFailure<void>(SongRepositoryErrorCode.notFound);
  }

  @override
  Future<AppResult<void>> permanentlyDelete(SongId id) async {
    if (!_documents.containsKey(id) && !_trashed.contains(id)) {
      return songRepositoryFailure<void>(SongRepositoryErrorCode.notFound);
    }
    _documents.remove(id);
    _trashed.remove(id);
    _hashes.remove(id);
    return AppResult<void>.success(null);
  }

  /// Helper exposing the document map so tests can inspect the live
  /// state without going through [get] (which copies by
  /// value-equality on [SongDocument]).
  // ignore: unused_element
  Iterable<MapEntry<SongId, SongDocument>> debugEntries() {
    return _documents.entries;
  }

  String _documentHash(SongDocument document) {
    final map = <String, dynamic>{
      'id': document.id.value,
      'revision': document.revision,
      'metadata': <String, dynamic>{
        'title': document.metadata.title,
        'artist': document.metadata.artist,
        'tags': List<String>.from(document.metadata.tags),
        'album': document.metadata.album,
        'composer': document.metadata.composer,
        'copyright': document.metadata.copyright,
        'notes': document.metadata.notes,
        'defaultCapo': document.metadata.defaultCapo,
        'originalKey': document.metadata.originalKey,
      },
    };
    return crypto.sha256.convert(utf8.encode(jsonEncode(map))).toString();
  }

  static SongDocument _copyWithRevision(SongDocument source, int revision) {
    return SongDocument(
      schemaVersion: source.schemaVersion,
      id: source.id,
      revision: revision,
      metadata: source.metadata,
      source: source.source,
      createdAt: source.createdAt,
      updatedAt: source.updatedAt,
      assets: source.assets,
      markers: source.markers,
      tracks: source.tracks,
      sections: source.sections,
      measures: source.measures,
      tempoMap: source.tempoMap,
      meterMap: source.meterMap,
      keyMap: source.keyMap,
    );
  }
}

// Uses dart:convert's jsonEncode / utf8 for the document hash. The
// fake intentionally bypasses the codec so tests don't drag the
// codec's exception list into the test surface.

// end of in_memory_song_repository.dart
