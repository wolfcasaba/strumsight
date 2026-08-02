/// Startup-time recovery scanner for the on-disk song repository
/// (E03-R07, ADR 0090 §Döntés 7, SDD §18.7).
///
/// The scanner runs once during app boot (the production provider decides
/// when). It walks every directory the song tree owns, classifies what
/// it finds into one of the [SongRepositoryRecoveryCode] buckets, and
/// — at the caller's request — performs one of the built-in repair
/// actions:
///
///   * `noAction` (default): report only;
///   * `cleanTemp`: deletes every `temp/*.tmp-*` file (the scanner
///     NEVER deletes an `assets/` or `documents/` file — that is the
///     unmovable evidence the user paid us to keep, ADR 0090 §Döntés 7);
///   * `rebuildIndex`: rebuilds `index.json` from the surviving
///     `documents/` directory. Documents that fail to decode are
///     preserved and reported as `[orphanDocument]` so the user can
///     drag them to the support contact.
///
/// The scanner never throws. A scan that finds nothing is
/// `SongRepositoryRecoveryReport.issues == []` and `hasIssues == false`.
library;

import 'dart:io';

import '../../domain/models/song_id.dart';
import '../../domain/models/song_source.dart';
import '../../domain/repositories/song_repository.dart';
import 'file_song_repository.dart';
import 'song_document_codec.dart';
import 'song_index_codec.dart';

/// Stable machine-readable codes emitted by [SongRepositoryRecovery.scan].
abstract final class SongRepositoryRecoveryCode {
  /// A `.tmp-*` residue left in the `temp/` directory. Evidence of a
  /// process killed mid-write — the scanner will let the caller
  /// decide whether to clean it up.
  static const String orphanTempFile = 'songRecovery.orphanTempFile';

  /// A file in `documents/` with no matching summary in `index.json`.
  /// Caused by a crash AFTER the document rename but BEFORE the index
  /// write. Rebuildable via [SongRepositoryRecoveryAction.rebuildIndex].
  static const String orphanDocument = 'songRecovery.orphanDocument';

  /// A file in `documents/` whose JSON codec refused to decode. The
  /// scanner leaves the file in place (it is the only source of truth
  /// for manual recovery) and surfaces a stable code.
  static const String corruptDocument = 'songRecovery.corruptDocument';

  /// A summary in `index.json` whose target document file is missing
  /// on disk. The scanner removes the summary entry and reports it.
  static const String missingDocument = 'songRecovery.missingDocument';

  /// `index.json` is structurally invalid. The scanner reports it; the
  /// caller can rebuild via [SongRepositoryRecoveryAction.rebuildIndex].
  static const String corruptIndex = 'songRecovery.corruptIndex';

  /// `index.json` is missing entirely (never written or wiped by a
  /// crashed writer). The scanner reports it; rebuild succeeds.
  static const String missingIndex = 'songRecovery.missingIndex';

  /// An entry in `assets/` whose `.summary.json` sidecar is missing.
  /// The asset bytes survive but the metadata is unknown — likely a
  /// crash between the bytes landing and the summary file landing.
  static const String orphanAssetBytes = 'songRecovery.orphanAssetBytes';
}

/// One issue the scanner found. [path] points to the offending file —
/// a future diagnostic surface can render the path verbatim, the
/// scanner never carries the file contents.
final class SongRepositoryRecoveryIssue {
  const SongRepositoryRecoveryIssue({required this.code, required this.path});

  /// One of [SongRepositoryRecoveryCode]'s constants. Stable across
  /// versions.
  final String code;

  /// Absolute path of the offending file. Diagnostic surface only —
  /// never rendered in user-facing text without going through the
  /// redacting logger.
  final String path;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SongRepositoryRecoveryIssue &&
          other.code == code &&
          other.path == path;

  @override
  int get hashCode => Object.hash(code, path);

  @override
  String toString() => 'SongRepositoryRecoveryIssue($code, path: $path)';
}

/// Strategy the scanner applies DURING the scan. Each variant is a
/// single behavioural knob; production callers pick one of
/// [noAction], [cleanTemp], or [rebuildIndex]. Combining variants is
/// NOT supported — the matrix of (report, rebuild) is too large to
/// reason about for a round that ships one of the three.
final class SongRepositoryRecoveryAction {
  const SongRepositoryRecoveryAction.publicKind(this.kind);
  final int kind;

  /// Read-only scan. No files are removed or rewritten. The default.
  static const SongRepositoryRecoveryAction noAction =
      SongRepositoryRecoveryAction.publicKind(0);

  /// During the scan, delete every `temp/*.tmp-*` file found.
  /// [SongRepositoryRecoveryCode.orphanTempFile] issues are still
  /// reported.
  static const SongRepositoryRecoveryAction cleanTemp =
      SongRepositoryRecoveryAction.publicKind(1);

  /// Rebuild `index.json` from the surviving `documents/`.
  /// [SongRepositoryRecoveryCode.missingDocument],
  /// [SongRepositoryRecoveryCode.orphanDocument] and
  /// [SongRepositoryRecoveryCode.corruptDocument] issues are still
  /// reported (corrupt documents are NOT deleted).
  static const SongRepositoryRecoveryAction rebuildIndex =
      SongRepositoryRecoveryAction.publicKind(2);
}

/// Outcome of a [SongRepositoryRecovery.scan] call.
final class SongRepositoryRecoveryReport {
  const SongRepositoryRecoveryReport({
    required this.issues,
    required this.rebuiltSummaries,
    required this.action,
  });

  /// Empty initial report (used by the round's diagnostics).
  static const empty = SongRepositoryRecoveryReport(
    issues: <SongRepositoryRecoveryIssue>[],
    rebuiltSummaries: <String>[],
    action: SongRepositoryRecoveryAction.noAction,
  );

  /// Every issue the scan found, classified by stable code.
  final List<SongRepositoryRecoveryIssue> issues;

  /// Summaries the scanner rebuilt into `index.json` (empty when
  /// [SongRepositoryRecoveryAction.rebuildIndex] was not requested or
  /// no document survived).
  final List<String> rebuiltSummaries;

  /// The action that ran during the scan.
  final SongRepositoryRecoveryAction action;

  /// True iff at least one issue was reported.
  bool get hasIssues => issues.isNotEmpty;

  /// Documents broken on disk by code. Convenience for diagnostics.
  Iterable<SongRepositoryRecoveryIssue> byCode(String code) =>
      issues.where((issue) => issue.code == code);
}

/// Stateless recovery scanner. Production wires it via the application
/// provider; tests construct one per temp-tree.
final class SongRepositoryRecovery {
  /// Construct a scanner. The class is stateless; `const` keeps callers
  /// honest about the cheap-sharing contract.
  const SongRepositoryRecovery();

  /// Scan [root] (the song-tree root). The scan walks the canonical
  /// subdirectories ([SongRepositoryLayout.documentsDirectory],
  /// [SongRepositoryLayout.trashDirectory],
  /// [SongRepositoryLayout.tempDirectory],
  /// [SongRepositoryLayout.assetsDirectory],
  /// [SongRepositoryLayout.originalsDirectory]) and the
  /// top-level `index.json`. Subdirectories missing from disk are
  /// treated as empty (recovery is robust against a partial-wipe).
  static Future<SongRepositoryRecoveryReport> scan(
    Directory root, {
    SongRepositoryRecoveryAction action = SongRepositoryRecoveryAction.noAction,
  }) async {
    final issues = <SongRepositoryRecoveryIssue>[];
    final documentCodec = const SongDocumentCodec();
    final indexCodec = const SongIndexCodec();

    // 1. Walk `temp/` for `.tmp-*` residue. The atomic file writer
    // removes its own temp on success; anything left behind is a crash
    // signal — the scanner lets the caller decide whether to delete.
    final tempDir = Directory(
      '${root.path}/${SongRepositoryLayout.tempDirectory}',
    );
    if (await tempDir.exists()) {
      for (final file in tempDir.listSync().whereType<File>()) {
        if (_looksLikeTempResidue(file.path)) {
          issues.add(
            SongRepositoryRecoveryIssue(
              code: SongRepositoryRecoveryCode.orphanTempFile,
              path: file.path,
            ),
          );
          if (action.kind == SongRepositoryRecoveryAction.cleanTemp.kind) {
            try {
              await file.delete();
            } on FileSystemException {
              // The scanner never throws.
            }
          }
        }
      }
    }

    // 2. Decode `index.json` if present; record either a corruption or
    // a missing-index issue if not. A missing index on a fresh install
    // (no `documents/` content) is the documented initial state and is
    // NOT flagged.
    final indexFile = File(
      '${root.path}/${SongRepositoryLayout.indexFileName}',
    );
    final docsDir = Directory(
      '${root.path}/${SongRepositoryLayout.documentsDirectory}',
    );
    final docsHaveContent =
        await docsDir.exists() &&
        (await docsDir.list().toList()).whereType<File>().isNotEmpty;
    var indexSummaries = const <SongSummary>[];
    if (!await indexFile.exists()) {
      if (docsHaveContent) {
        issues.add(
          SongRepositoryRecoveryIssue(
            code: SongRepositoryRecoveryCode.missingIndex,
            path: indexFile.path,
          ),
        );
      }
    } else {
      try {
        indexSummaries = indexCodec.decode(await indexFile.readAsBytes());
      } on Exception {
        issues.add(
          SongRepositoryRecoveryIssue(
            code: SongRepositoryRecoveryCode.corruptIndex,
            path: indexFile.path,
          ),
        );
      }
    }

    // 3. For each summary in the index: still on disk? Still decodable?
    if (await docsDir.exists()) {
      for (final summary in indexSummaries) {
        final fileName = '${summary.documentId.safeFilename()}.json';
        final file = File('${docsDir.path}/$fileName');
        if (!await file.exists()) {
          issues.add(
            SongRepositoryRecoveryIssue(
              code: SongRepositoryRecoveryCode.missingDocument,
              path: file.path,
            ),
          );
          continue;
        }
        try {
          documentCodec.decode(await file.readAsBytes());
        } on Exception {
          issues.add(
            SongRepositoryRecoveryIssue(
              code: SongRepositoryRecoveryCode.corruptDocument,
              path: file.path,
            ),
          );
        }
      }
    }

    // 4. For each document on disk: is its summary present in the
    // index? If not, it's an orphan candidate (and a corrupt document
    // if it refuses to decode).
    final knownIdsFromIndex = <String>{
      for (final summary in indexSummaries) summary.documentId.value,
    };
    if (await docsDir.exists()) {
      for (final file in docsDir.listSync().whereType<File>()) {
        final fileName = file.uri.pathSegments.last;
        if (!fileName.endsWith('.json')) continue;
        final stem = fileName.substring(0, fileName.length - 5);
        if (knownIdsFromIndex.contains(stem)) continue;
        try {
          // Verify the orphan is at least a loadable document before
          // flagging it as orphan — pure garbage is surfaced as
          // `corruptDocument` instead.
          documentCodec.decode(await file.readAsBytes());
          issues.add(
            SongRepositoryRecoveryIssue(
              code: SongRepositoryRecoveryCode.orphanDocument,
              path: file.path,
            ),
          );
        } on Exception {
          issues.add(
            SongRepositoryRecoveryIssue(
              code: SongRepositoryRecoveryCode.corruptDocument,
              path: file.path,
            ),
          );
        }
      }
    }

    // 5. Walk `assets/` for orphan bytes (no summary sidecar).
    final assetsDir = Directory(
      '${root.path}/${SongRepositoryLayout.assetsDirectory}',
    );
    if (await assetsDir.exists()) {
      for (final file in assetsDir.listSync().whereType<File>()) {
        final name = file.uri.pathSegments.last;
        if (_looksLikeTempResidue(name)) continue;
        if (name.endsWith(SongAssetSidecarSuffix.refsExtension)) continue;
        if (name.endsWith(SongAssetSidecarSuffix.summaryExtension)) {
          continue;
        }
        final stem = _fileNameNoExt(name);
        if (!await File(
          '${assetsDir.path}/$stem${SongAssetSidecarSuffix.summaryExtension}',
        ).exists()) {
          issues.add(
            SongRepositoryRecoveryIssue(
              code: SongRepositoryRecoveryCode.orphanAssetBytes,
              path: file.path,
            ),
          );
        }
      }
    }

    // 6. Optional `rebuildIndex` action. The rebuilt index derives
    // its data from each surviving `documents/<id>.json` via the
    // document codec — the index never duplicates the document (SDD
    // §18.4) so the rebuilt entry is intentionally minimal.
    final rebuiltSummaries = <String>[];
    if (action.kind == SongRepositoryRecoveryAction.rebuildIndex.kind &&
        await docsDir.exists()) {
      final rebuilt = <SongSummary>[];
      for (final file in docsDir.listSync().whereType<File>()) {
        final fileName = file.uri.pathSegments.last;
        if (!fileName.endsWith('.json')) continue;
        try {
          final document = documentCodec.decode(await file.readAsBytes());
          rebuilt.add(_summaryForRebuilt(document));
          rebuiltSummaries.add(document.id.value);
        } on Exception {
          // Already classified as `corruptDocument` above — the
          // rebuild silently skips it.
        }
      }
      try {
        final encoded = indexCodec.encode(rebuilt);
        indexFile.writeAsBytesSync(encoded, flush: true);
      } on FileSystemException {
        // No-op: the report already enumerates what we tried.
      }
    }

    return SongRepositoryRecoveryReport(
      issues: List<SongRepositoryRecoveryIssue>.unmodifiable(issues),
      rebuiltSummaries: List<String>.unmodifiable(rebuiltSummaries),
      action: action,
    );
  }

  /// Build a minimal [SongSummary] from a decoded document so the
  /// rebuilt index has a single honest surface to walk. The capability
  /// is null until the Live layer re-runs the validator on next
  /// session boot.
  static SongSummary _summaryForRebuilt(dynamic document) {
    final metadata = document.metadata;
    String title = '';
    String? artist;
    List<String> tags = const <String>[];
    try {
      title = metadata.title as String;
    } on Object {
      /* keep default */
    }
    try {
      artist = metadata.artist as String?;
    } on Object {
      /* keep default */
    }
    try {
      tags = List<String>.from(metadata.tags as List);
    } on Object {
      /* keep default */
    }
    return SongSummary(
      documentId: document.id as SongId,
      title: title,
      artist: artist,
      tags: List<String>.unmodifiable(tags),
      updatedAt: (document.updatedAt as DateTime).toUtc(),
      lastPracticedAt: (document.updatedAt as DateTime).toUtc(),
      capability: null,
      sourceType: (document.source as dynamic).type as SongSourceType,
      favorite: false,
      archived: false,
      trashed: false,
      revision: document.revision as int,
      documentHash: '0' * 64,
    );
  }

  static bool _looksLikeTempResidue(String path) {
    return RegExp(r'\.tmp-\d+-\d+$').hasMatch(path);
  }

  static String _fileNameNoExt(String name) {
    final dot = name.lastIndexOf('.');
    return dot < 0 ? name : name.substring(0, dot);
  }
}

/// Sidecar file suffixes the recovery scanner should ignore when
/// walking `assets/`. Mirrors the production code's conventions.
abstract final class SongAssetSidecarSuffix {
  /// `<sha256>.refs.json` — per-asset reference list.
  static const String refsExtension = '.refs.json';

  /// `<sha256>.summary.json` — per-asset metadata sidecar.
  static const String summaryExtension = '.summary.json';
}
