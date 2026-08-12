/// Versioned, file-backed audio-analysis repository contract
/// (ADR 0239, E06-R21 brief §1 / §4, SDD §24.1).
///
/// This interface is the **only** Audio Analysis entry point a future
/// Library V2 surface (E06-R30) consumes. Today (the current round) no
/// production caller is wired — the repository is constructed by the
/// Riverpod provider in `application/analysis_providers.dart` and
/// exercised by the round-gate tests.
///
/// The contract deliberately mirrors [LibraryRepository] (six methods)
/// so the future migration from V1 to V2 is a one-line controller
/// swap rather than a re-architecture.
library;

import 'package:meta/meta.dart';

import '../../../core/foundation/app_result.dart';
import 'analysis_document.dart';
import 'analysis_summary.dart';
import 'audio_retention_policy.dart';

/// Stable, machine-readable codes the repository can emit. Kept in the
/// domain layer so the UI / presentation layer can localise by code
/// without importing the data-layer codec or the storage exception
/// (brief §6 "stable typed failures").
abstract final class AnalysisRepositoryErrorCode {
  /// The repository could not read or write to the filesystem.
  static const String io = 'analysis.repository.io';

  /// The on-disk document failed the SHA-256 checksum check.
  static const String checksumMismatch =
      'analysis.repository.checksum_mismatch';

  /// The on-disk document failed the codec decode (corrupt JSON,
  /// schema-version mismatch, missing field).
  static const String corruptDocument = 'analysis.repository.corrupt';

  /// The on-disk summary index failed the index codec.
  static const String corruptIndex = 'analysis.repository.index_corrupt';

  /// The requested id is not present in the repository (neither live
  /// nor trashed).
  static const String notFound = 'analysis.repository.not_found';

  /// The input document failed the schema-version guard (the V2 codec
  /// refuses to encode anything but the current schema version).
  static const String unsupportedSchema =
      'analysis.repository.unsupported_schema';
}

/// Input value object for the `save` / `replace` operations.
///
/// The [title] and [customTitle] fields are kept here (not on
/// [AnalysisDocument], per ADR 0221 §Döntés 1) so the legacy
/// `AnalyzedSession.title` / `customTitle` survive V1→V2 migration
/// without coupling the document model to the UI metadata.
@immutable
final class AnalysisSaveRequest {
  const AnalysisSaveRequest({
    required this.document,
    required this.title,
    required this.customTitle,
    this.retention = AudioRetentionPolicy.defaultPolicy,
  });

  /// The V2 document to persist. The repository encodes it via the
  /// existing [AnalysisDocumentCodec] (E06-R03, ADR 0215/0221).
  final AnalysisDocument document;

  /// Legacy / display title. Empty string is allowed (a fresh capture
  /// before any title is set). The repository preserves the value
  /// verbatim.
  final String title;

  /// Whether [title] was a user-chosen name. Default false.
  final bool customTitle;

  /// Retention policy. Defaults to [AudioRetentionPolicy.defaultPolicy]
  /// which is `keepOriginal: false` — i.e. no raw audio is ever
  /// persisted.
  final AudioRetentionPolicy retention;
}

/// Versioned, file-backed audio-analysis repository (ADR 0239, SDD
/// §24.1).
abstract interface class AnalysisRepository {
  /// List every summary, ordered newest `createdAt` first.
  ///
  /// Implementation MUST read only the summary index; the brief §6
  /// "summary-olvasás" cell proves the document decoder is invoked
  /// exactly zero times during this call. If the index is missing or
  /// corrupt the repository rebuilds it from the document files (the
  /// rebuild is the ONLY legitimate exception to the
  /// zero-decoder-call rule).
  Future<AppResult<List<AnalysisSummary>>> list();

  /// Load one full [AnalysisDocument] by its stable id. Returns
  /// [AnalysisRepositoryErrorCode.notFound] when the id is absent.
  Future<AppResult<AnalysisDocument>> getById(String id);

  /// Persist a new analysis. Returns a typed failure
  /// ([AnalysisRepositoryErrorCode.unsupportedSchema]) when the
  /// document's `schemaVersion` does not match the codec.
  Future<AppResult<void>> save(AnalysisSaveRequest request);

  /// Replace the on-disk document for an existing id. The summary
  /// `title` / `customTitle` are refreshed from [request].
  Future<AppResult<void>> replace(String id, AnalysisSaveRequest request);

  /// Rename a document — updates only the summary index's
  /// `title`/`customTitle` fields, never the document itself.
  Future<AppResult<void>> rename({
    required String id,
    required String newTitle,
  });

  /// Permanently delete one document and its index entry.
  Future<AppResult<void>> delete(String id);
}
