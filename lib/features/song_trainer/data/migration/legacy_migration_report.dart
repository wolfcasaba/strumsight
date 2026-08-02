/// Stable, adapter-local migration fidelity report (E03-R06, ADR 0116 §Döntés 1).
///
/// The report is the SINGLE, immutable shape the legacy Song/Setlist adapter
/// returns to surface source→target fidelity findings. It is intentionally
/// **not** an extension of `SongValidationReport` (which audits the
/// document's own internal consistency, ADR 0114) nor of `ImportWarning`
/// (which is the UI-targeted warning projection). Migration fidelity lives
/// on a third axis: "did the adapter have to repair, drop or synthesise
/// something on the way from legacy input to V2 document?".
///
/// All codes are stable, additive machine identifiers. New codes may be
/// added in later rounds; existing codes are never renamed or repointed,
/// the codec round-trip keys off the literal value.
library;

import 'package:meta/meta.dart';

/// Stable machine-readable codes attached to a [LegacyMigrationIssue.code].
abstract final class LegacyMigrationCode {
  /// Legacy `Song.pattern` length did not match `beatsPerBar * 2`; the
  /// adapter truncated or rest-padded the pattern to fit the meter.
  static const String patternLengthFitted =
      'legacyMigration.pattern.lengthFitted';

  /// The legacy record's `bpm` was outside the documented SongTrainer range
  /// (1..400); the adapter clamped it to the nearest valid value.
  static const String bpmClamped = 'legacyMigration.bpm.clamped';

  /// A `Setlist` referenced the same song id more than once. The adapter
  /// preserved both copies in order (legacy `Setlist.combine` already does so
  /// on the legacy side; the V2 boundary surfaces it so the caller can show
  /// a recovery hint).
  static const String setlistDuplicateRetained =
      'legacyMigration.setlist.duplicateRetained';

  /// A `Setlist` referenced a song id absent from the supplied songbook. The
  /// entry was skipped (no crash) and the id is reported.
  static const String setlistReferenceUnresolved =
      'legacyMigration.setlist.referenceUnresolved';
}

/// One entry on the migration fidelity report.
///
/// The [code] is one of [LegacyMigrationCode]'s constants — callers must
/// branch on the literal value, not on [message], which is only intended
/// for logs.
@immutable
final class LegacyMigrationIssue {
  /// Stable migration issue constructor.
  const LegacyMigrationIssue({required this.code, required this.message});

  /// Stable, machine-readable code from [LegacyMigrationCode].
  final String code;

  /// Locale-independent English message intended for logs. The UI maps
  /// [code] to a localised string at display time. No UI strings are
  /// permitted in this domain model.
  final String message;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LegacyMigrationIssue &&
          other.code == code &&
          other.message == message;

  @override
  int get hashCode => Object.hash(code, message);
}

/// Immutable fidelity report returned by every adapter call.
///
/// The [issues] list is unmodifiable and sorted by `(code asc)` so two
/// adapters on equal inputs return equal reports (§6 acceptance
/// "ismételt futtatásra azonos"). The [warningSummary] is the flat,
/// deterministic projection persisted on `SongSource.warningSummary` for
/// codec round-trip — the typed report is the adapter's return shape,
/// the string list is what survives the save/load cycle
/// (ADR 0116 §Döntés 1).
@immutable
final class LegacyMigrationReport {
  /// Stable report constructor — the issues list is sorted and deduped
  /// by `(code asc)` so two calls on equal inputs return equal reports.
  factory LegacyMigrationReport.from(Iterable<LegacyMigrationIssue> issues) {
    if (issues.isEmpty) return empty;
    final deduped = <String, LegacyMigrationIssue>{};
    for (final issue in issues) {
      deduped.putIfAbsent(issue.code, () => issue);
    }
    final sorted = deduped.values.toList()
      ..sort((a, b) => a.code.compareTo(b.code));
    return LegacyMigrationReport._(sorted);
  }

  /// Private constructor — use [LegacyMigrationReport.from] (or the
  /// [empty] constant) to build a report. The issues list is expected to
  /// already be sorted and deduped.
  const LegacyMigrationReport._(this.issues);

  /// Every distinct issue the adapter emitted, in deterministic
  /// `(code asc)` order.
  final List<LegacyMigrationIssue> issues;

  /// Flat, deterministic, sorted list of issue codes — the projection
  /// that survives the codec round-trip in `SongSource.warningSummary`.
  /// Derived from [issues] on access (the issues list is already sorted,
  /// so a copy-and-sort keeps the contract while allowing the field to
  /// be initialised in a const constructor).
  List<String> get warningSummary {
    if (issues.isEmpty) return const <String>[];
    final codes = <String>[for (final issue in issues) issue.code]..sort();
    return List<String>.unmodifiable(codes);
  }

  /// An empty report — the common case for a clean, in-bounds legacy
  /// record.
  static const LegacyMigrationReport empty = LegacyMigrationReport._(
    <LegacyMigrationIssue>[],
  );

  /// `true` iff no repair / drop / synthesise was needed.
  bool get isEmpty => issues.isEmpty;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! LegacyMigrationReport) return false;
    if (other.issues.length != issues.length) return false;
    for (var i = 0; i < issues.length; i++) {
      if (other.issues[i] != issues[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(issues);
}
