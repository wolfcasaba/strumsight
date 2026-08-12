/// Lightweight summary record for the on-disk index sidecar
/// (ADR 0239 §Döntés 1 + §Döntés 8, E06-R21 brief §4).
///
/// The summary is what `list()` returns — it carries only the
/// metadata needed to render the Library list without ever decoding
/// the full V2 [AnalysisDocument]. The codec for [AnalysisDocument]
/// (E06-R03, ADR 0221) MUST stay independent of this type: the
/// summary lives in `index.json` while the full document lives in
/// `documents/<id>.json`.
///
/// Legacy fields ([title], [customTitle]) are intentionally kept on
/// the summary (not on [AnalysisDocument], per ADR 0221 §Döntés 1):
/// the legacy `AnalyzedSession.title` and `AnalyzedSession.customTitle`
/// survive V1→V2 migration by living next to the document.
library;

import 'package:meta/meta.dart';

/// Index-side summary for one persisted analysis document.
///
/// A summary never decodes the full document. `list()` builds the
/// result by reading only `index.json`; the brief §6 acceptance
/// "summary-olvasás" cell proves the document decoder is invoked
/// exactly zero times during a `list()` call (recovery excepted).
@immutable
final class AnalysisSummary {
  const AnalysisSummary({
    required this.documentId,
    required this.title,
    required this.customTitle,
    required this.createdAt,
    required this.completionStatus,
    required this.documentHash,
    required this.sizeBytes,
  });

  /// Stable identifier — the legacy session id for migrated records,
  /// the engine-emitted id for fresh captures.
  final String documentId;

  /// Legacy title (auto-title like "C · G" or user-renamed). Empty
  /// string is allowed for fresh captures that have not been titled
  /// yet.
  final String title;

  /// Whether [title] was a user-chosen name. Auto-titles (chord
  /// summaries) are false; user rename marks the summary true so
  /// display layers skip capo-transposition (r114 legacy behaviour).
  final bool customTitle;

  /// UTC timestamp of the original analysis. Used for the cap eviction
  /// order — the OLDEST `createdAt` is evicted when the 100-document
  /// cap is exceeded.
  final DateTime createdAt;

  /// "complete" / "degraded" / "cancelled" / "failed" — surfaced as a
  /// string so the index codec does not need to depend on the V2 enum
  /// tree (which lives in the document, not the index).
  final String completionStatus;

  /// Lower-case SHA-256 hex of the on-disk document bytes. Used to
  /// detect corruption on read and to surface a stable integrity
  /// signal across the index/document boundary.
  final String documentHash;

  /// On-disk byte size of the document JSON. Surfaced so the cap
  /// accounting (and tests asserting "no PCM on disk") can compare
  /// against the document size without re-reading the file.
  final int sizeBytes;

  AnalysisSummary copyWith({String? title, bool? customTitle}) =>
      AnalysisSummary(
        documentId: documentId,
        title: title ?? this.title,
        customTitle: customTitle ?? this.customTitle,
        createdAt: createdAt,
        completionStatus: completionStatus,
        documentHash: documentHash,
        sizeBytes: sizeBytes,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AnalysisSummary &&
          other.documentId == documentId &&
          other.title == title &&
          other.customTitle == customTitle &&
          other.createdAt.toUtc().isAtSameMomentAs(createdAt.toUtc()) &&
          other.completionStatus == completionStatus &&
          other.documentHash == documentHash &&
          other.sizeBytes == sizeBytes;

  @override
  int get hashCode => Object.hash(
    documentId,
    title,
    customTitle,
    createdAt.toUtc(),
    completionStatus,
    documentHash,
    sizeBytes,
  );

  @override
  String toString() =>
      'AnalysisSummary('
      'documentId: $documentId, '
      'title: $title, '
      'customTitle: $customTitle, '
      'createdAt: ${createdAt.toUtc().toIso8601String()}, '
      'completionStatus: $completionStatus, '
      'documentHash: $documentHash, '
      'sizeBytes: $sizeBytes)';
}
