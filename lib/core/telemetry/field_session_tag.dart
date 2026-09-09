/// The internal-Alpha FIELD SESSION tag (SDD Ch14 Kör 40, ADR 0542 D7).
///
/// A field-study capture has to be attributable to a study run — otherwise
/// eight testers' sessions are an undifferentiated pile — but "attributable
/// to a run" must never become "attributable to a person or a handset". So
/// the tag carries exactly two things: a CLOSED cohort value and the same
/// rotating pseudonym beta telemetry uses. There is no participant name, no
/// e-mail, no handset model, no free note field on this type; the study's
/// qualitative findings live in the human protocol document
/// (`docs/release/ch14-r40-field-study.md`), not in a capture header.
///
/// Fail-closed by construction: [resolve] returns `null` — no tag at all —
/// unless the build flag is on AND the participant opted in AND a live
/// pseudonym exists. A capture with no tag is a valid capture; a capture
/// with a half-formed tag would be a fabricated study record.
library;

import 'telemetry_consent.dart';

/// Which study a tagged capture belongs to. Closed on purpose: a free
/// "study name" string is how a participant's name ends up in a header.
enum FieldStudyCohort {
  /// SDD Ch14 Kör 40 — the internal Alpha field study (8 guitarists).
  ch14InternalAlpha,
}

/// Which scripted task the capture was recorded under (Kör 40 task list).
/// The protocol document's task list and this enum are one taxonomy.
enum FieldStudyTask {
  setup,
  freePlay,
  guidedPattern,
  chordChanges,
  noisyRoom,
}

/// The tag attached to one Lab/diagnostics capture during a field study.
final class FieldSessionTag {
  const FieldSessionTag({
    required this.cohort,
    required this.task,
    required this.pseudonym,
  });

  final FieldStudyCohort cohort;
  final FieldStudyTask task;

  /// The rotating pseudonym from the participant's consent record — the
  /// only identifier on the tag.
  final TelemetryPseudonymId pseudonym;

  /// Resolves the tag for a capture, or `null` when any gate is closed.
  ///
  /// [fieldSessionTaggingEnabled] is `FeatureFlags
  /// .recognitionFieldSessionTaggingEnabled`; [enrolled] is the
  /// participant's own opt-in, which is separate from telemetry consent
  /// because agreeing to be in a study is not the same act as agreeing to
  /// aggregate reporting.
  static FieldSessionTag? resolve({
    required bool fieldSessionTaggingEnabled,
    required bool enrolled,
    required FieldStudyCohort cohort,
    required FieldStudyTask task,
    required TelemetryPseudonymId? pseudonym,
  }) {
    if (!fieldSessionTaggingEnabled) return null;
    if (!enrolled) return null;
    if (pseudonym == null) return null;
    return FieldSessionTag(cohort: cohort, task: task, pseudonym: pseudonym);
  }

  /// The capture-header form. Only the three closed members appear, and the
  /// key set is the same allowlist discipline the telemetry codec uses.
  Map<String, Object?> toHeader() => <String, Object?>{
    'fieldCohort': cohort.name,
    'fieldTask': task.name,
    'fieldPseudonymId': pseudonym.value,
  };

  /// Every key [toHeader] may emit — declared so a guard test can compare
  /// against it instead of against the implementation.
  static const Set<String> headerKeys = <String>{
    'fieldCohort',
    'fieldTask',
    'fieldPseudonymId',
  };

  @override
  bool operator ==(Object other) =>
      other is FieldSessionTag &&
      other.cohort == cohort &&
      other.task == task &&
      other.pseudonym == pseudonym;

  @override
  int get hashCode => Object.hash(cohort, task, pseudonym);

  @override
  String toString() =>
      'FieldSessionTag(${cohort.name}, ${task.name}, ${pseudonym.value})';
}
