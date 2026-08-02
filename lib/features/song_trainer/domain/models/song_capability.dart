/// Stable capability and profile model for a [SongDocument]
/// (E03-R05, ADR 0114 §Döntés 1 + §Döntés 2, SDD §7 + §12).
///
/// Capability is the **honest, independent answer** to "what can the
/// app safely do with this document?" — it is NEVER collapsed into a
/// single boolean, and it is NEVER derived from the validation
/// severity directly. Severity (`fatal`/`warning`) decides persist
/// eligibility; capability decides display and scoring. The two axes
/// are intentional, separately queryable, and the §6 acceptance
/// matrix explicitly depends on the four combinations
/// (persist=true/false × scoring=true/false) being representable.
library;

import 'package:meta/meta.dart';

/// Stable profiles the Song Trainer recognises (E03-R05, SDD §7).
///
/// A profile is the consumer side that asks the question; the report
/// answers the profile's question independently of the others.
enum SongCapabilityProfile {
  /// "Can I render an import-time preview?" — never blocked by
  /// capability issues; only the **fatal** validation severity can
  /// turn this off.
  importPreview('importPreview'),

  /// "Can I write this document to the repository?" — gated by
  /// validation severity alone (any `fatal` issue ⇒ false).
  persist('persist'),

  /// "Can I drive the practice / trainer flow on this document?"
  /// Display survives; scoring capability gates the per-track trainer
  /// features.
  trainer('trainer'),

  /// "Can I export this document to a downstream format?" Mirrors
  /// [persist] for now (no consumer-only export gates are defined
  /// yet); kept as a separate profile so the future exporter can
  /// branch without a schema change.
  export('export');

  const SongCapabilityProfile(this.code);

  /// Stable, machine-readable identifier persisted on the wire.
  final String code;
}

/// Resolves a stable [SongCapabilityProfile] code, or `null` for an
/// unknown / future code (callers fail closed).
SongCapabilityProfile? songCapabilityProfileFromCode(String code) {
  for (final value in SongCapabilityProfile.values) {
    if (value.code == code) return value;
  }
  return null;
}

/// Independent display / scoring capability for a single axis of a
/// single track (E03-R05, ADR 0114 §Döntés 2).
///
/// Display survives every non-fatal warning. Scoring is downgraded
/// independently, per axis, so a single document can simultaneously
/// `display = true` (chord chart renders) and `scoring = false` (the
/// matcher refuses to score unsupported chords). Combining the two
/// into a single boolean is explicitly forbidden by §5 kötött döntés
/// 2.
@immutable
final class SongCapability {
  /// Constructs a single capability answer for one axis.
  const SongCapability({required this.display, required this.scoring});

  /// Default capability (everything works). Used by the resolver for
  /// documents with no warnings.
  static const SongCapability full = SongCapability(
    display: true,
    scoring: true,
  );

  /// Capability is denied entirely — neither display nor scoring
  /// survives (the fatal path; only [SongValidationSeverity.fatal]
  /// issues can produce this).
  static const SongCapability none = SongCapability(
    display: false,
    scoring: false,
  );

  /// Display works, but scoring refuses to consume this axis (the
  /// typical warning shape — unsupported chord, polyphonic pitch).
  static const SongCapability displayOnly = SongCapability(
    display: true,
    scoring: false,
  );

  /// `true` when the UI may render this axis. Independent of
  /// [scoring] — callers must check both fields.
  final bool display;

  /// `true` when the scorer may consume this axis. Independent of
  /// [display] — a `false` here means the matcher refuses to grade
  /// this dimension even though the UI still renders it.
  final bool scoring;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SongCapability &&
          other.display == display &&
          other.scoring == scoring;

  @override
  int get hashCode => Object.hash(display, scoring);
}

/// Stable chord-axis capability answer (E03-R05).
///
/// Chord capability is **always** `displayOnly` for documents that
/// contain an unsupported chord — the chart still renders (the
/// `Chord.label` is an unvalidated wrapper, ADR 0113 §Döntés 1) but
/// the matcher refuses to score an unknown symbol against the
/// detector vocabulary. The capability answer is derived from the
/// validator's chord-support classification (ADR 0114 §Döntés 1).
@immutable
final class SongChordCapability {
  const SongChordCapability({
    required this.display,
    required this.scoring,
    required this.hasUnsupportedChord,
  });

  /// Display always works on the chord axis (the Chord wrapper
  /// carries the raw label verbatim).
  final bool display;

  /// Scoring works only when no chord event used an unsupported
  /// chord symbol; a single unsupported chord ⇒ `false`.
  final bool scoring;

  /// `true` when at least one chord event used an unsupported symbol;
  /// the import preview still works but the UI must surface the
  /// warning. Independent of [scoring] — the two fields intentionally
  /// agree in the current implementation, but the split is kept so
  /// future partial scoring can downgrade scoring without changing
  /// the data the UI surfaces.
  final bool hasUnsupportedChord;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SongChordCapability &&
          other.display == display &&
          other.scoring == scoring &&
          other.hasUnsupportedChord == hasUnsupportedChord;

  @override
  int get hashCode => Object.hash(display, scoring, hasUnsupportedChord);
}

/// Stable pitch-axis capability answer for a `NoteTrack`
/// (E03-R05, ADR 0114 §Döntés 2).
///
/// Pitch display always works; pitch scoring is `false` for a
/// polyphonic track (multiple pitches overlapped on the timeline,
/// distinct from the tie-candidate count). The split mirrors
/// [SongChordCapability] — display survives, scoring is independently
/// downgraded.
@immutable
final class SongPitchCapability {
  const SongPitchCapability({
    required this.display,
    required this.scoring,
    required this.isMonophonic,
  });

  /// Display works for every track — the UI renders note events
  /// verbatim.
  final bool display;

  /// Scoring works only when the [NoteTrackAnalyzer] reports
  /// `isMonophonic == true`. A polyphonic track keeps display on but
  /// the matcher refuses to grade pitch (rhythm / strum scoring can
  /// still consume the same events).
  final bool scoring;

  /// Mirror of [NoteTrackAnalysis.isMonophonic]; preserved on the
  /// capability so consumers do not have to re-run the analyzer.
  final bool isMonophonic;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SongPitchCapability &&
          other.display == display &&
          other.scoring == scoring &&
          other.isMonophonic == isMonophonic;

  @override
  int get hashCode => Object.hash(display, scoring, isMonophonic);
}

/// Top-level capability report for a single profile (E03-R05).
///
/// The report carries the per-axis answers (chord / pitch) AND the
/// coarse `canDisplay` / `canScore` roll-ups the §6 acceptance matrix
/// uses; the roll-ups are computed independently from the per-axis
/// fields so a future per-axis expansion cannot silently flip them.
@immutable
final class SongCapabilityReport {
  /// Constructs a top-level capability report for a single profile.
  const SongCapabilityReport({
    required this.profile,
    required this.chord,
    required this.pitch,
    required this.canPersist,
    required this.canImportPreview,
    required this.canExport,
    required this.canTrain,
  });

  /// The profile this report answers.
  final SongCapabilityProfile profile;

  /// Chord-axis answer.
  final SongChordCapability chord;

  /// Pitch-axis answer.
  final SongPitchCapability pitch;

  /// `true` iff this profile is allowed to call the repository write
  /// path. Driven by validation severity alone (ADR 0114 §Döntés 2).
  final bool canPersist;

  /// `true` iff the import preview may render this document. Never
  /// blocked by capability; only by fatal validation issues.
  final bool canImportPreview;

  /// `true` iff the export pipeline may emit this document. Mirrors
  /// [canPersist] for now (no consumer-only export gates are defined
  /// yet); kept as a separate flag so the future exporter can branch
  /// without a schema change.
  final bool canExport;

  /// `true` iff the trainer flow can drive this document. Always
  /// `true` for non-fatal documents — the trainer degrades per-axis
  /// via the chord / pitch answers, not at the document level.
  final bool canTrain;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SongCapabilityReport) return false;
    return other.profile == profile &&
        other.chord == chord &&
        other.pitch == pitch &&
        other.canPersist == canPersist &&
        other.canImportPreview == canImportPreview &&
        other.canExport == canExport &&
        other.canTrain == canTrain;
  }

  @override
  int get hashCode => Object.hash(
    profile,
    chord,
    pitch,
    canPersist,
    canImportPreview,
    canExport,
    canTrain,
  );
}
