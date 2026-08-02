/// Stable import-time warning model used by the validator and the
/// capability resolver (E03-R05, ADR 0114 §Döntés 2).
///
/// The warning is the single, immutable shape the Song Trainer domain
/// uses to surface non-fatal, recoverable import issues (e.g. an
/// unsupported chord extension, a polyphonic note track, or a
/// normalised tie group with mismatched pitches). It is intentionally
/// kept independent of [SongSource.warningSummary] — the source keeps
/// a flat string list for codec round-tripping, while this model is
/// the rich, typed projection used by validation reports and the
/// capability resolver.
///
/// Severity is constrained to `warning` here: fatal issues are
/// reported through [SongValidationIssue] with a different, fatal
/// severity. The split keeps the capability resolver honest
/// (ADR 0114 §Döntés 2 — severity alone decides persist eligibility,
/// the capability decision is a separate axis).
library;

import 'package:meta/meta.dart';

/// Stable machine-readable codes attached to an [ImportWarning.code].
///
/// New codes are additive; existing codes must never be renamed or
/// repointed, the codec and audit log key off the literal value.
abstract final class ImportWarningCode {
  /// A `ChordTrack` event carried a chord the local capability
  /// resolver cannot score (e.g. `Cmaj7`, `G/B`, exotic extensions).
  /// Display is still supported; scoring is downgraded.
  static const String chordUnsupported = 'importWarning.chord.unsupported';

  /// A `NoteTrack` produced a non-monophonic [NoteTrackAnalysis]
  /// (overlapping notes with different pitches). Display works; pitch
  /// scoring is downgraded, rhythm scoring survives.
  static const String notePolyphonic = 'importWarning.note.polyphonic';

  /// A `NoteTrack` carried one or more notes whose technique is an
  /// [SongNoteTechniqueKind] the local analyzer does not yet
  /// understand. The technique is preserved on disk; scoring treats
  /// the affected notes as unscored.
  static const String techniqueUnknown = 'importWarning.technique.unknown';

  /// A `SongStrumEvent` arrived without a determinate direction.
  /// Display works; direction-scoring refuses to score that event but
  /// rhythm scoring survives.
  static const String strumDirectionUnknown =
      'importWarning.strum.directionUnknown';
}

/// Stable, non-fatal, recoverable import warning (E03-R05, ADR 0114
/// §Döntés 2). Display survives the warning; the matching scoring
/// capability is independently downgraded by the capability resolver.
@immutable
final class ImportWarning {
  /// Stable, non-fatal, recoverable import warning.
  ///
  /// The [code] is one of [ImportWarningCode]'s constants — callers
  /// should branch on the literal value, not on [message], which is
  /// only intended for logging.
  ///
  /// The [message] is locale-independent English copy; the UI maps
  /// [code] to a localised string at display time. No UI strings are
  /// permitted in this domain model.
  const ImportWarning({required this.code, required this.message});

  /// Stable, machine-readable warning code from [ImportWarningCode].
  final String code;

  /// Locale-independent English message intended for logs. The UI maps
  /// [code] to a localised string at display time.
  final String message;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ImportWarning && other.code == code && other.message == message;

  @override
  int get hashCode => Object.hash(code, message);
}
