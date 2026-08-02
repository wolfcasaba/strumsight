/// Stable validation report and issue model for a [SongDocument]
/// (E03-R05, ADR 0114 §Döntés 2, SDD §7 + §12).
///
/// The report is the SINGLE, immutable shape the Song Trainer domain
/// uses to communicate validation findings to the importer / preview
/// UI / capability resolver. It never throws — unknown / corrupt
/// input is reported through this report so the caller can branch on
/// the result instead of catching exceptions (§6 acceptance:
/// "Validator ismeretlen/rossz inputnál reportot ad, nem nyers
/// exceptiont").
///
/// Severity drives persist eligibility; capability is computed
/// independently by [SongCapabilityResolver]. The two answers are
/// deliberately NOT merged here (ADR 0114 §Döntés 2 — see
/// `Kötelező megkülönböztető mátrix`).
library;

import 'package:meta/meta.dart';

import 'import_warning.dart';

/// Stable validation severity (E03-R05, ADR 0114 §Döntés 2).
///
/// `fatal` ⇒ `canPersist = false` for every profile. `warning` keeps
/// persist alive but is independently consumed by the capability
/// resolver.
enum SongValidationSeverity {
  /// The document cannot be persisted or rendered. The validator must
  /// surface at least one fatal issue; the capability resolver
  /// answers `false` for every profile's `canPersist`.
  fatal('fatal'),

  /// Non-fatal, recoverable issue. Persist survives; the capability
  /// resolver may downgrade scoring on the matching axis.
  warning('warning');

  const SongValidationSeverity(this.code);

  /// Stable, machine-readable identifier persisted on the wire.
  final String code;
}

/// Resolves a stable [SongValidationSeverity] code, or `null` for an
/// unknown / future code (callers fail closed).
SongValidationSeverity? songValidationSeverityFromCode(String code) {
  for (final value in SongValidationSeverity.values) {
    if (value.code == code) return value;
  }
  return null;
}

/// Stable, machine-readable codes attached to a
/// [SongValidationIssue.code].
///
/// New codes are additive; existing codes must never be renamed or
/// repointed — the validator output is part of the persistence /
/// audit contract.
abstract final class SongValidationCode {
  /// Document-level: a `SongSection.endMeasureExclusive` exceeds the
  /// document's `measures.length` — visible only at the document
  /// level (each model constructor validates its own state in
  /// isolation).
  static const String sectionRangeExceedsMeasures =
      'songValidation.section.rangeExceedsMeasures';

  /// Document-level: a `SongSection` overlaps another section's
  /// measure range. Visible only at the document level.
  static const String sectionRangeOverlap =
      'songValidation.section.rangeOverlap';

  /// Track-level: a `SongStrumEvent.targetChordId` references a
  /// `SongChordEvent.id` not present in the document. Visible only at
  /// the document level.
  static const String strumTargetChordMissing =
      'songValidation.strum.targetChordMissing';

  /// Track-level: a `SongStrumEvent` had a null direction at import
  /// time (the importer could not determine the stroke direction).
  /// Surfaced as a warning, not a fatal issue.
  static const String strumDirectionUnknown =
      'songValidation.strum.directionUnknown';

  /// Track-level: a chord event carried an unsupported chord symbol
  /// (see ADR 0114 §Döntés 1 — the resolver uses its own, domain-local
  /// grammar, never the practice-feature dictionary).
  static const String chordUnsupported = 'songValidation.chord.unsupported';

  /// Track-level: a note track produced a non-monophonic analysis.
  static const String notePolyphonic = 'songValidation.note.polyphonic';

  /// Track-level: a note event used an unknown performance technique.
  /// The technique is preserved on disk; scoring is downgraded.
  static const String techniqueUnknown = 'songValidation.technique.unknown';
}

/// Stable validation issue (E03-R05, ADR 0114 §Döntés 2).
///
/// Issues are the immutable record the validator returns. The
/// caller (importer, UI, capability resolver) branches on
/// [severity] + [code]; [message] is locale-independent English copy
/// intended for logs only — the UI maps [code] to a localised string.
@immutable
final class SongValidationIssue {
  /// Stable validation issue constructor.
  ///
  /// The [code] is one of [SongValidationCode]'s constants — callers
  /// must branch on the literal value, not on [message], which is
  /// only intended for logging.
  const SongValidationIssue({
    required this.severity,
    required this.code,
    required this.message,
  });

  /// Severity bucket. `fatal` ⇒ no profile may persist the document.
  final SongValidationSeverity severity;

  /// Stable, machine-readable code from [SongValidationCode].
  final String code;

  /// Locale-independent English message intended for logs. The UI
  /// maps [code] to a localised string at display time.
  final String message;

  /// `true` iff this issue is fatal (any profile's `canPersist` must
  /// be `false`).
  bool get isFatal => severity == SongValidationSeverity.fatal;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SongValidationIssue &&
          other.severity == severity &&
          other.code == code &&
          other.message == message;

  @override
  int get hashCode => Object.hash(severity, code, message);
}

/// Stable validation report (E03-R05, ADR 0114 §Döntés 2).
///
/// The validator never throws — corrupt or unknown input is reported
/// as a fatal issue. The report carries both the issue list (driven
/// by the document state) and the corresponding non-fatal warnings
/// projected into the typed [ImportWarning] shape, so the import
/// preview UI has ONE canonical source of truth to render.
@immutable
final class SongValidationReport {
  /// Stable validation report constructor.
  ///
  /// The [issues] list is unmodifiable; the [warnings] list is
  /// unmodifiable. Both are exposed through the report so the caller
  /// can use either view without re-projecting the data.
  const SongValidationReport({required this.issues, required this.warnings});

  /// Every issue the validator found, in a deterministic order
  /// (issues sorted by `severity asc, code asc`).
  final List<SongValidationIssue> issues;

  /// Projected, non-fatal warnings in the typed [ImportWarning]
  /// shape (subset of [issues]). The projection is one-to-one on
  /// `code` and is sorted by `code asc` for determinism.
  final List<ImportWarning> warnings;

  /// `true` iff at least one issue is fatal (any profile's
  /// `canPersist` must be `false`).
  bool get hasFatalIssue => issues.any((issue) => issue.isFatal);

  /// `true` iff no fatal issue exists.
  bool get isPersistable => !hasFatalIssue;

  /// An empty report (zero issues, zero warnings). Convenient for the
  /// common "valid document" case.
  static const SongValidationReport empty = SongValidationReport(
    issues: <SongValidationIssue>[],
    warnings: <ImportWarning>[],
  );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SongValidationReport) return false;
    if (other.issues.length != issues.length) return false;
    if (other.warnings.length != warnings.length) return false;
    for (var i = 0; i < issues.length; i++) {
      if (other.issues[i] != issues[i]) return false;
    }
    for (var i = 0; i < warnings.length; i++) {
      if (other.warnings[i] != warnings[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(issues), Object.hashAll(warnings));
}
