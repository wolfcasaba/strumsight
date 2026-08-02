/// Provenance and origin metadata for a [SongDocument] (ADR 0089 §Döntés 4,
/// SDD §9.4).
///
/// The `type` is a stable enum ([SongSourceType]) so legacy-parity audits and
/// importer-specific fidelity reports can branch on the original format
/// without leaking parser details into the domain. The remaining fields —
/// original filename, SHA-256, import time, importer version, optional
/// format-specific version and warning summary, optional original-asset
/// reference — are the minimum needed for an idempotent re-import to
/// recognise a known source without silent merging.
library;

import 'song_id.dart';

/// Stable exceptions for [SongSource] validation.
class SongSourceValidationException implements Exception {
  SongSourceValidationException._(this.code);

  /// One of [SongSourceValidationCode]'s constants.
  final String code;

  @override
  String toString() => 'SongSourceValidationException($code)';
}

/// Stable machine-readable codes emitted by [SongSource] validation.
abstract final class SongSourceValidationCode {
  static const String originalFileNameEmpty =
      'songSource.originalFileName.empty';
  static const String sha256Invalid = 'songSource.sha256.invalid';
  static const String importerVersionEmpty = 'songSource.importerVersion.empty';
  static const String formatVersionEmpty = 'songSource.formatVersion.empty';
  static const String warningSummaryTooLong =
      'songSource.warningSummary.tooLong';
  static const String warningEntryEmpty =
      'songSource.warningSummary.entry.empty';
  static const String warningEntryTooLong =
      'songSource.warningSummary.entry.tooLong';
}

/// Origin category of a [SongDocument].
///
/// Codes are stable machine identifiers: a rename of an enum constant must
/// keep its persisted `code` unchanged or migration will be required.
enum SongSourceType {
  /// Persisted under the legacy `SharedPreferences`-based `Song` schema
  /// (`legacyLocal`) — used by the migration adapter only.
  legacyLocal('legacyLocal'),

  /// Authored directly inside the StrumSight Song Editor.
  createdInApp('createdInApp'),

  /// Exported then re-imported from a StrumSight native JSON document.
  strumSightJson('strumSightJson'),

  /// MusicXML score file (`.musicxml`).
  musicXml('musicXml'),

  /// Compressed MusicXML (`.mxl`).
  compressedMusicXml('compressedMusicXml'),

  /// Standard MIDI File (`.mid`, `.midi`).
  midi('midi'),

  /// Guitar Pro file (`.gp*`) — only available when the platform / licence
  /// feasibility gate (SDD §11.7, E03-R13) is satisfied.
  guitarPro('guitarPro');

  const SongSourceType(this.code);

  /// Stable persisted identifier independent of enum order.
  final String code;
}

/// Resolves a stable [SongSourceType] code. Returns `null` for an unknown
/// code so the codec can fail closed (§6 acceptance criteria — "Unknown
/// source type policy fail-closed, silent default not acceptable").
SongSourceType? songSourceTypeFromCode(String code) {
  for (final value in SongSourceType.values) {
    if (value.code == code) return value;
  }
  return null;
}

/// Bound on the number of import warnings kept on the document. Generous
/// next to any realistic importer — it exists to reject a corrupt record.
const int maxSongSourceWarningCount = 64;

/// Bound on the length of one persisted warning summary code.
const int maxSongSourceWarningEntryLength = 256;

/// Provenance chain attached to a [SongDocument].
final class SongSource {
  SongSource({
    required this.type,
    required this.originalFileName,
    required this.sha256,
    required this.importedAt,
    required this.importerVersion,
    this.formatVersion,
    this.warningSummary = const <String>[],
    this.originalAssetId,
  }) {
    if (originalFileName.trim().isEmpty) {
      throw SongSourceValidationException._(
        SongSourceValidationCode.originalFileNameEmpty,
      );
    }
    if (importerVersion.trim().isEmpty) {
      throw SongSourceValidationException._(
        SongSourceValidationCode.importerVersionEmpty,
      );
    }
    if (formatVersion != null && formatVersion!.trim().isEmpty) {
      throw SongSourceValidationException._(
        SongSourceValidationCode.formatVersionEmpty,
      );
    }
    if (!_isHex64(sha256)) {
      throw SongSourceValidationException._(
        SongSourceValidationCode.sha256Invalid,
      );
    }
    if (warningSummary.length > maxSongSourceWarningCount) {
      throw SongSourceValidationException._(
        SongSourceValidationCode.warningSummaryTooLong,
      );
    }
    for (final entry in warningSummary) {
      if (entry.isEmpty) {
        throw SongSourceValidationException._(
          SongSourceValidationCode.warningEntryEmpty,
        );
      }
      if (entry.length > maxSongSourceWarningEntryLength) {
        throw SongSourceValidationException._(
          SongSourceValidationCode.warningEntryTooLong,
        );
      }
    }
  }

  /// Stable origin enum.
  final SongSourceType type;

  /// The original file name (with extension) the user opened. Persisted as
  /// display, not as a path — the repository resolves the actual file via
  /// the [originalAssetId] / SHA-256 pair.
  final String originalFileName;

  /// Lower-case SHA-256 of the original bytes (or the canonical-form bytes
  /// for compressed formats). Used for duplicate detection and integrity
  /// verification, never for ID derivation.
  final String sha256;

  /// UTC timestamp of the import attempt. Persisted as UTC ISO-8601 by the
  /// codec (SDD §9.4).
  final DateTime importedAt;

  /// Stable `importer@version` identifier; lets a future build know which
  /// importer produced the document for re-import parity reporting.
  final String importerVersion;

  /// Format-specific version (e.g. MusicXML 3.1) when the importer can
  /// declare it; `null` when not applicable or unknown.
  final String? formatVersion;

  /// Summary of importer warnings (e.g. `unknown_element`, `truncated_bar`).
  /// Stable, code-shaped strings — the UI maps them to a localised
  /// description at display time.
  final List<String> warningSummary;

  /// Optional [SongAssetId] pointing to the preserved original file, when the
  /// user opted in to keep it (E03-R10).
  final SongAssetId? originalAssetId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SongSource &&
          other.type == type &&
          other.originalFileName == originalFileName &&
          other.sha256 == sha256 &&
          other.importedAt.toUtc().microsecondsSinceEpoch ==
              importedAt.toUtc().microsecondsSinceEpoch &&
          other.importerVersion == importerVersion &&
          other.formatVersion == formatVersion &&
          _listEquals(other.warningSummary, warningSummary) &&
          other.originalAssetId == originalAssetId;

  @override
  int get hashCode => Object.hash(
    type,
    originalFileName,
    sha256,
    importedAt.toUtc().microsecondsSinceEpoch,
    importerVersion,
    formatVersion,
    Object.hashAll(warningSummary),
    originalAssetId,
  );

  static bool _isHex64(String value) {
    if (value.length != 64) return false;
    for (var index = 0; index < value.length; index++) {
      final rune = value.codeUnitAt(index);
      final isDigit = rune >= 0x30 && rune <= 0x39;
      final isLowerHex = rune >= 0x61 && rune <= 0x66;
      if (!isDigit && !isLowerHex) return false;
    }
    return true;
  }

  static bool _listEquals(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (a[index] != b[index]) return false;
    }
    return true;
  }
}
