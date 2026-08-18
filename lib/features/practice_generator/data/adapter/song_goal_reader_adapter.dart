/// Caller-fed [SongDocument] → song-goal read projection (ADR 0318).
///
/// The adapter is the only place in the Practice Generator that touches the
/// Song Trainer surface, and it touches **only** the public domain barrel
/// (`package:strumsight/features/song_trainer/domain/public.dart`). It never
/// opens a Song Trainer repository, controller, provider, or any non-public
/// file. The Song Trainer `Hotspot` / `SongTrainerResult` types are
/// application-internal — this adapter has no opinion on them (ADR 0318
/// §Döntés 1).
///
/// The adapter is pure: it accepts a [SongDocument] the caller already holds
/// and an optional `expectedRevision` (the revision the caller previously
/// knew about) and returns a [SongGoalReadOutcome]. It never reads bytes,
/// never queries an asset store, and never opens a track — it only inspects
/// the structural surface the document already exposes. A missing usable
/// asset reference for a section therefore surfaces as
/// `usableAssetReference == null` in the projection — an explicit signal
/// the planner can route on, never a silent skip (ADR 0318 §Döntés 2,
/// ADR 0262 §5).
library;

import 'package:strumsight/features/song_trainer/domain/public.dart';

/// One section as the planner sees it, paired with its (optional) usable
/// public asset reference.
///
/// `usableAssetReference == null` is an **explicit** signal: the document
/// does not expose a public asset reference for this section. It is never
/// a silent skip — the planner decides what to do with the explicit gap
/// (fallback, request asset, decline the section, …).
final class SongGoalSectionView {
  SongGoalSectionView({
    required this.sectionId,
    required this.sectionName,
    required this.kind,
    required this.startMeasure,
    required this.endMeasureExclusive,
    required this.usableAssetReference,
  });

  /// Stable identifier of the section in the source document.
  final SongSectionId sectionId;

  /// Human-readable section name as authored (trimmed, non-empty).
  final String sectionName;

  /// Pedagogical role of the section (intro / verse / chorus / bridge / …).
  final SongSectionKind kind;

  /// Inclusive measure index where the section starts.
  final int startMeasure;

  /// Exclusive measure index where the section ends.
  final int endMeasureExclusive;

  /// Public asset reference the section can route through, or `null` when
  /// no usable public asset reference is exposed for this section.
  final SongAssetReference? usableAssetReference;
}

/// The structured outcome of one [SongGoalReaderAdapter.read] call.
///
/// The three variants are deliberately non-overlapping so the planner can
/// branch without falling back to a default:
///   * [SongGoalReadSuccess] — sections are available; the planner may
///     proceed (subject to the documented `missingUsableAssetCount`).
///   * [SongGoalReadStaleRevision] — the document's revision does not match
///     the caller's expected revision; the planner must surface the
///     divergence (ADR 0318 §Döntés 2, ADR 0262 §5) and refuse to plan
///     against the stale expectation.
///   * [SongGoalReadNoSections] — the document carries zero sections; the
///     planner has nothing to plan against and must treat the song goal as
///     structurally empty.
sealed class SongGoalReadOutcome {
  const SongGoalReadOutcome();
}

/// The happy-path read: the document is the one the caller expected (or no
/// expectation was supplied), it has at least one section, and every
/// section is reported with its (possibly null) public asset reference.
final class SongGoalReadSuccess extends SongGoalReadOutcome {
  SongGoalReadSuccess({
    required this.documentId,
    required this.documentRevision,
    required this.expectedRevision,
    required Iterable<SongAssetReference> documentAssetReferences,
    required Iterable<SongGoalSectionView> sections,
  }) : documentAssetReferences = List<SongAssetReference>.unmodifiable(
         documentAssetReferences,
       ),
       sections = List<SongGoalSectionView>.unmodifiable(sections);

  /// Identifier of the source document (ADR 0089 §Döntés 2).
  final SongId documentId;

  /// Current revision the document exposes (ADR 0089 §Döntés 3).
  final int documentRevision;

  /// Revision the caller previously knew about, or `null` when the caller
  /// had no prior expectation (a first read).
  final int? expectedRevision;

  /// Every public asset reference the document exposes at the document
  /// level. Unmodifiable; may be empty when the document carries no assets.
  final List<SongAssetReference> documentAssetReferences;

  /// Per-section projection. `usableAssetReference` is `null` for sections
  /// the document does not back with a public asset reference — an
  /// explicit signal, never a silent skip (ADR 0318 §Döntés 2).
  final List<SongGoalSectionView> sections;

  /// Number of sections that arrived without a public asset reference.
  /// Surfaced as a field so the planner can route without re-scanning the
  /// list.
  int get missingUsableAssetCount =>
      sections.where((section) => section.usableAssetReference == null).length;

  /// True when the document carries zero usable asset references at all
  /// (neither the document-level list nor any per-section reference is
  /// non-null).
  bool get hasNoUsableAssets =>
      documentAssetReferences.isEmpty &&
      missingUsableAssetCount == sections.length;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SongGoalReadSuccess &&
          other.documentId == documentId &&
          other.documentRevision == documentRevision &&
          other.expectedRevision == expectedRevision &&
          _listEquals(other.documentAssetReferences, documentAssetReferences) &&
          _listEquals(other.sections, sections);

  @override
  int get hashCode => Object.hash(
    documentId,
    documentRevision,
    expectedRevision,
    Object.hashAll(documentAssetReferences),
    Object.hashAll(sections),
  );
}

/// The document's revision does not match the caller's `expectedRevision`.
///
/// The planner must surface the divergence and refuse to plan against the
/// stale expectation — this is the explicit "elavult dal-revízió detektált"
/// branch the brief A6 cell requires.
final class SongGoalReadStaleRevision extends SongGoalReadOutcome {
  const SongGoalReadStaleRevision({
    required this.documentId,
    required this.actualRevision,
    required this.expectedRevision,
  });

  final SongId documentId;
  final int actualRevision;
  final int expectedRevision;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SongGoalReadStaleRevision &&
          other.documentId == documentId &&
          other.actualRevision == actualRevision &&
          other.expectedRevision == expectedRevision;

  @override
  int get hashCode => Object.hash(documentId, actualRevision, expectedRevision);
}

/// The document is current but exposes zero sections. The planner has
/// nothing to plan against; this is the explicit "hiányzó szakasz" branch
/// the brief A5 cell requires (no silent skip).
final class SongGoalReadNoSections extends SongGoalReadOutcome {
  const SongGoalReadNoSections({
    required this.documentId,
    required this.documentRevision,
  });

  final SongId documentId;
  final int documentRevision;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SongGoalReadNoSections &&
          other.documentId == documentId &&
          other.documentRevision == documentRevision;

  @override
  int get hashCode => Object.hash(documentId, documentRevision);
}

/// Pure adapter that turns a caller-fed [SongDocument] into a
/// [SongGoalReadOutcome].
///
/// The adapter never reads a Song Trainer repository, controller, or
/// provider. It only inspects the structural surface the document itself
/// already exposes — sections, the document-level asset list, and the
/// monotonic revision counter (ADR 0089 §Döntés 3).
final class SongGoalReaderAdapter {
  const SongGoalReaderAdapter();

  /// Read [document] and compare against [expectedRevision] (when supplied).
  ///
  /// Returns a [SongGoalReadOutcome]. The contract:
  ///   * When `expectedRevision != null && expectedRevision != document.revision`
  ///     → [SongGoalReadStaleRevision].
  ///   * When the document has zero sections → [SongGoalReadNoSections].
  ///   * Otherwise → [SongGoalReadSuccess] with every section's explicit
  ///     (`null` when absent) usable asset reference.
  SongGoalReadOutcome read({
    required SongDocument document,
    int? expectedRevision,
  }) {
    final documentId = document.id;
    final documentRevision = document.revision;
    if (expectedRevision != null && expectedRevision != documentRevision) {
      return SongGoalReadStaleRevision(
        documentId: documentId,
        actualRevision: documentRevision,
        expectedRevision: expectedRevision,
      );
    }
    final sourceSections = document.sections;
    if (sourceSections.isEmpty) {
      return SongGoalReadNoSections(
        documentId: documentId,
        documentRevision: documentRevision,
      );
    }
    final documentAssetReferences = document.assets;
    final views = <SongGoalSectionView>[
      for (final section in sourceSections)
        SongGoalSectionView(
          sectionId: section.id,
          sectionName: section.name,
          kind: section.kind,
          startMeasure: section.startMeasure,
          endMeasureExclusive: section.endMeasureExclusive,
          // Per ADR 0318 §Döntés 2: the adapter does not attempt to pair a
          // section with a document-level asset reference. The document
          // surface does not expose a section→asset mapping in the public
          // contract; pairing would require either non-public data or a
          // hotspot (which lives outside the public barrel). The explicit
          // null forces the planner to make a fallback decision instead of
          // silently assuming a section is asset-backed.
          usableAssetReference: null,
        ),
    ];
    return SongGoalReadSuccess(
      documentId: documentId,
      documentRevision: documentRevision,
      expectedRevision: expectedRevision,
      documentAssetReferences: documentAssetReferences,
      sections: views,
    );
  }
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) return false;
  }
  return true;
}
