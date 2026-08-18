/// Shared builders for the E07-R24 song-goal test surface.
///
/// Every helper here is a thin wrapper over the already-validated
/// `public.dart` constructors (the song-goal planner + reader adapter +
/// Song Trainer public domain barrel) — no domain decision lives here,
/// only fixture assembly.
library;

import 'package:strumsight/features/practice_generator/public.dart';
import 'package:strumsight/features/song_trainer/domain/public.dart';

/// A fixed 64-char lower-case hex string used as a sha256 stub. Stable
/// across runs so test failures are reproducible.
const String _kFixtureSha256 =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

/// Build a [SongAssetReference] for a section fixture.
SongAssetReference buildSongAssetReference({String id = 'asset-1'}) =>
    SongAssetReference(
      id: SongAssetId(id),
      sha256: _kFixtureSha256,
      extension: 'mp3',
      byteLength: 1024,
      mimeType: 'audio/mpeg',
      durationMs: 60 * 1000,
    );

/// Build a single [SongSection] with the given kind + measure span.
SongSection buildSongSection({
  required String id,
  required String name,
  required SongSectionKind kind,
  required int startMeasure,
  required int endMeasureExclusive,
}) => SongSection(
  id: SongSectionId(id),
  name: name,
  startMeasure: startMeasure,
  endMeasureExclusive: endMeasureExclusive,
  kind: kind,
);

/// Build the document-level [SongMetadata] every fixture document uses.
SongMetadata buildSongMetadata() =>
    SongMetadata(title: 'Fixture Song', artist: 'Fixture Artist');

/// Build the [SongSource] every fixture document uses.
SongSource buildSongSource() => SongSource(
  type: SongSourceType.createdInApp,
  originalFileName: 'fixture.strumsight',
  sha256: _kFixtureSha256,
  importedAt: DateTime.utc(2026, 8, 1),
  importerVersion: 'fixture@1.0.0',
);

/// Build a [SongDocument] for the song-goal tests.
///
/// Caller supplies the [revision], the [sections] and the optional
/// [assets]. The remaining fields are stable so test failures are
/// reproducible.
SongDocument buildSongDocument({
  required int revision,
  required List<SongSection> sections,
  List<SongAssetReference>? assets,
  String id = 'fixture-song-1',
}) => SongDocument(
  schemaVersion: songDocumentSchemaVersion,
  id: SongId(id),
  revision: revision,
  metadata: buildSongMetadata(),
  source: buildSongSource(),
  createdAt: DateTime.utc(2026, 8, 1),
  updatedAt: DateTime.utc(2026, 8, 1),
  assets: assets ?? const <SongAssetReference>[],
  sections: sections,
);

/// Build a [SongGoalSectionView] with the supplied (optional) asset.
SongGoalSectionView buildSongGoalSectionView({
  required String sectionId,
  required String sectionName,
  required SongSectionKind kind,
  required int startMeasure,
  required int endMeasureExclusive,
  SongAssetReference? usableAssetReference,
}) => SongGoalSectionView(
  sectionId: SongSectionId(sectionId),
  sectionName: sectionName,
  kind: kind,
  startMeasure: startMeasure,
  endMeasureExclusive: endMeasureExclusive,
  usableAssetReference: usableAssetReference,
);

/// Build a [SongGoalReadSuccess] from a list of section views.
SongGoalReadSuccess buildSongGoalReadSuccess({
  required List<SongGoalSectionView> sections,
  required int revision,
  List<SongAssetReference>? documentAssetReferences,
  int? expectedRevision,
  String documentId = 'fixture-song-1',
}) => SongGoalReadSuccess(
  documentId: SongId(documentId),
  documentRevision: revision,
  expectedRevision: expectedRevision,
  documentAssetReferences:
      documentAssetReferences ?? const <SongAssetReference>[],
  sections: sections,
);

/// Build a [SongGoalBlockDraft] for the planner tests.
SongGoalBlockDraft buildSongGoalBlockDraft({
  required SongGoalSectionView sectionView,
  Iterable<String> targetSkillIds = const <String>[],
  Iterable<String> prerequisiteSkillIds = const <String>[],
  int estimatedMinutes = 5,
}) => SongGoalBlockDraft(
  sectionView: sectionView,
  targetSkillIds: targetSkillIds,
  prerequisiteSkillIds: prerequisiteSkillIds,
  estimatedMinutes: estimatedMinutes,
);

/// Build a [SongGoalPlanningRequest] with sensible defaults for the
/// planner tests.
SongGoalPlanningRequest buildSongGoalPlanningRequest({
  required SongGoalReadOutcome read,
  required Iterable<SongGoalBlockDraft> drafts,
  required LocalDate scheduledDate,
  required LocalDate songTargetDate,
  int weekAvailableMinutes = 600,
  Iterable<String> knownSkillIds = const <String>[],
  SongGoalRatioPolicy? ratioPolicy,
  SongGoalPhasePolicy? phasePolicy,
}) => SongGoalPlanningRequest(
  read: read,
  drafts: drafts,
  scheduledDate: scheduledDate,
  songTargetDate: songTargetDate,
  weekAvailableMinutes: weekAvailableMinutes,
  knownSkillIds: knownSkillIds,
  ratioPolicy: ratioPolicy,
  phasePolicy: phasePolicy,
);
