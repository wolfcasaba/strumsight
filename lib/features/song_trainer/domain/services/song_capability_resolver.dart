/// Stable, side-effect-free capability resolver (E03-R05, ADR 0114
/// §Döntés 1 + §Döntés 2, SDD §7 + §12).
///
/// The resolver translates a [SongValidationReport] into the four
/// independent answers the §6 acceptance matrix needs:
///
///   * `canPersist` — driven by validation severity alone; any
///     fatal issue ⇒ `false` for every profile (ADR 0114 §Döntés 2).
///   * `canImportPreview` — never blocked by capability; only a
///     fatal validation issue can turn it off.
///   * `canTrain` — always `true` for non-fatal documents; the
///     trainer degrades per-axis via the chord / pitch answers.
///   * `canExport` — mirrors `canPersist` for now; a separate flag
///     so the future exporter can branch without a schema change.
///
/// The chord / pitch axes are computed independently from the
/// non-fatal issue list — the resolver never collapses severity and
/// capability into a single boolean. The §6 matrix's four
/// combinations (persistable + scoring-downgraded, persistable +
/// full-scoring, persistable + zero-scoring) all remain
/// representable.
///
/// The resolver is **framework-independent**: no Flutter, Riverpod,
/// Dio, SharedPreferences, l10n or storage plugin import is allowed.
library;

import 'package:meta/meta.dart';

import '../models/song_capability.dart';
import '../models/song_validation_report.dart';

/// Pure, deterministic capability resolver (E03-R05).
@immutable
final class SongCapabilityResolver {
  /// Constructs a resolver. Stateless and pure; share a single
  /// instance per process.
  const SongCapabilityResolver();

  /// Resolves [report] into the canonical capability answer for
  /// [profile].
  ///
  /// The output is deterministic: equal reports produce equal
  /// reports for a given profile. The resolver never inspects the
  /// original document — it consumes only the validation report, so
  /// it remains a pure function of the report's content.
  SongCapabilityReport resolve({
    required SongValidationReport report,
    required SongCapabilityProfile profile,
  }) {
    final hasFatal = report.hasFatalIssue;
    final canPersist = !hasFatal;
    final chord = _chordCapability(report, hasFatal: hasFatal);
    final pitch = _pitchCapability(report, hasFatal: hasFatal);

    return SongCapabilityReport(
      profile: profile,
      chord: chord,
      pitch: pitch,
      canPersist: canPersist,
      canImportPreview: !hasFatal,
      canExport: canPersist,
      canTrain: !hasFatal,
    );
  }

  /// Computes the chord-axis capability from the report's
  /// non-fatal warnings. Display survives every non-fatal warning;
  /// a fatal validation issue disables display (and therefore
  /// scoring) for the whole axis (§5 kötött döntés 2 + ADR 0114
  /// §Döntés 1).
  SongChordCapability _chordCapability(
    SongValidationReport report, {
    required bool hasFatal,
  }) {
    final hasUnsupported = report.issues.any(
      (issue) =>
          issue.severity == SongValidationSeverity.warning &&
          issue.code == SongValidationCode.chordUnsupported,
    );
    return SongChordCapability(
      display: !hasFatal,
      scoring: !hasFatal && !hasUnsupported,
      hasUnsupportedChord: hasUnsupported,
    );
  }

  /// Computes the pitch-axis capability from the report's
  /// non-fatal warnings. Display survives every non-fatal warning;
  /// a fatal validation issue disables display (and therefore
  /// scoring) for the whole axis.
  SongPitchCapability _pitchCapability(
    SongValidationReport report, {
    required bool hasFatal,
  }) {
    final isPolyphonic = report.issues.any(
      (issue) =>
          issue.severity == SongValidationSeverity.warning &&
          issue.code == SongValidationCode.notePolyphonic,
    );
    return SongPitchCapability(
      display: !hasFatal,
      scoring: !hasFatal && !isPolyphonic,
      isMonophonic: !hasFatal && !isPolyphonic,
    );
  }
}
