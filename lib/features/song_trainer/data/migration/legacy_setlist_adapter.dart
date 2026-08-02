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
/// The adapter never persists anything (§3 "Kívül" — no V2 repository
/// write in this round). It produces a list of [SongDocument]s in the
/// same order as the legacy setlist, plus a single [LegacyMigrationReport]
/// summarising the fidelity decisions the adapter took.
library;

import 'package:meta/meta.dart';

import '../../domain/models/song_document.dart';
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
}
