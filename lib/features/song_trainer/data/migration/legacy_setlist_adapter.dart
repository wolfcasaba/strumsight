/// Lossless, deterministic adapter from a legacy [LegacySetlistRecord]
/// + a songbook of adapted V2 [SongDocument]s into the ordered list of
/// documents a setlist represents (E03-R06, ADR 0116, SDD Ch4 §3.4).
///
/// The adapter mirrors the legacy `Setlist.combine` contract at the
/// document boundary:
///
///   - Order is preserved (the songbook map is consulted, not sorted).
///   - Duplicates survive (a song referenced twice produces two documents
///     in the output list — no silent dedup).
///   - Missing references are SKIPPED, not thrown, and reported through
///     [LegacyMigrationCode.setlistReferenceUnresolved].
///
/// [adapt] never persists anything. [persistV2] is the explicit E03-R22
/// extension that writes the same order and unresolved references to a V2
/// repository after the lossless projection has been established.
library;

import 'package:meta/meta.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';

import '../../domain/models/song_document.dart';
import '../../domain/models/song_id.dart';
import '../../domain/models/song_setlist.dart';
import '../../domain/repositories/setlist_repository.dart';
import 'legacy_migration_report.dart';
import 'legacy_song_reader.dart';

/// Output of a single [LegacySetlistAdapter.adapt] call.
@immutable
final class LegacySetlistAdaptation {
  /// Stable constructor.
  const LegacySetlistAdaptation({
    required this.documents,
    required this.report,
    required this.unresolvedIds,
  });

  /// The adapted V2 documents in play order. Duplicates are preserved as
  /// separate entries (the caller may dedup later, the adapter does not).
  final List<SongDocument> documents;

  /// Fidelity report — empty when the songbook contained every song id
  /// the setlist referenced AND no id was duplicated.
  final LegacyMigrationReport report;

  /// The song ids the setlist referenced but the songbook did not
  /// contain. Order is preserved as the setlist declared them.
  final List<String> unresolvedIds;
}

/// Lossless, deterministic Setlist → ordered V2 document list adapter
/// (E03-R06, ADR 0116).
final class LegacySetlistAdapter {
  /// Stable constructor.
  const LegacySetlistAdapter();

  /// Resolve one legacy setlist against a songbook of already-adapted
  /// V2 documents.
  ///
  /// [songbook] is keyed by the legacy `Song.id`; the map is treated as
  /// the canonical "what is currently known" answer. Missing keys are
  /// reported, never synthesised.
  LegacySetlistAdaptation adapt(
    LegacySetlistRecord setlist,
    Map<String, SongDocument> songbook,
  ) {
    final issues = <LegacyMigrationIssue>[];
    final unresolved = <String>[];
    final out = <SongDocument>[];
    final seenIds = <String>{};

    for (final songId in setlist.songIds) {
      final document = songbook[songId];
      if (document == null) {
        unresolved.add(songId);
        issues.add(
          LegacyMigrationIssue(
            code: LegacyMigrationCode.setlistReferenceUnresolved,
            message:
                'Setlist ${setlist.id} referenced unknown song id '
                '"$songId"; entry skipped.',
          ),
        );
        continue;
      }
      out.add(document);
      if (!seenIds.add(songId)) {
        // Duplicate — first duplicate occurrence is the one that
        // triggers the report (idempotent).
        issues.add(
          LegacyMigrationIssue(
            code: LegacyMigrationCode.setlistDuplicateRetained,
            message:
                'Setlist ${setlist.id} referenced song id "$songId" '
                'more than once; both copies retained in order.',
          ),
        );
      }
    }

    return LegacySetlistAdaptation(
      documents: List<SongDocument>.unmodifiable(out),
      report: LegacyMigrationReport.from(issues),
      unresolvedIds: List<String>.unmodifiable(unresolved),
    );
  }

  /// Persist a V2 representation without dropping duplicate or unresolved
  /// legacy entries. A missing source becomes a recoverable V2 item rather
  /// than a thrown migration failure.
  Future<AppResult<SongSetlist>> persistV2(
    LegacySetlistRecord setlist,
    Map<String, SongDocument> songbook, {
    required SetlistRepository repository,
    required DateTime migratedAt,
  }) async {
    final setlistId = SongIdValidator.safeFilename(setlist.id);
    final items = <SongSetlistItem>[
      for (var index = 0; index < setlist.songIds.length; index++)
        SongSetlistItem(
          id: '$setlistId-$index',
          songId: SongId(setlist.songIds[index]),
          initialAvailability: songbook.containsKey(setlist.songIds[index])
              ? SetlistItemAvailability.ready
              : SetlistItemAvailability.missingSong,
        ),
    ];
    final v2 = SongSetlist(
      id: setlistId,
      name: setlist.name,
      items: items,
      createdAt: migratedAt.toUtc(),
      updatedAt: migratedAt.toUtc(),
    );
    final saved = await repository.save(v2);
    if (saved.isFailure) {
      return AppResult<SongSetlist>.failure(
        StorageFailure(
          code: 'legacySetlistAdapter.persist',
          cause: saved.failureOrNull,
        ),
      );
    }
    return AppResult<SongSetlist>.success(v2);
  }
}
