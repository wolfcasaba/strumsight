import 'package:meta/meta.dart';

/// In which recognition regime a Live detection engine was CONSTRUCTED
/// (E14-R30, ADR 0544 D1).
///
/// This is not a UI mode and not a runtime setting: it is a construction-time
/// property of the engine that decides whether an expected-chord hint is
/// admissible at all. The Live screen's product modes (Free Play / Guided
/// Pattern / Accuracy Check) map ONTO this enum, they are not this enum.
///
/// * [free] — nothing outside the audio may influence the chord verdict. The
///   expected-chord prior is not merely ignored, it cannot be BUILT: an
///   [ExpectedChordHint] does not exist for a free-mode engine, so the code
///   path that would apply it has no value to apply (ADR 0544 D2). A free
///   engine therefore produces bit-identical output whether or not a caller
///   pushes an expected chord into it.
/// * [guided] — a lesson/song target is known, so an [ExpectedChordHint] can
///   exist. Even then the hint is only a TIE-BREAKER (ADR 0544 D3): it never
///   enters the decoder's trellis and can never overturn audio evidence that
///   actually separates two chords.
enum RecognitionMode {
  free,
  guided;

  /// Whether an expected-chord hint may exist in this mode at all. The single
  /// machine-readable statement of ADR 0544 D2 — exhaustive, no `default`.
  bool get allowsExpectedChordPrior => switch (this) {
    RecognitionMode.free => false,
    RecognitionMode.guided => true,
  };
}

/// The ONLY carrier through which an expected-chord label can reach the chord
/// decoder (E14-R30, ADR 0544 D2).
///
/// The constructor is private to this library, so no caller anywhere in the
/// tree can hand the decoder a hint it did not obtain from [forMode]. And
/// [forMode] returns `null` for [RecognitionMode.free]. That is the whole
/// isolation guarantee, expressed in the type system instead of in a comment
/// or a screen-level `setExpectedChord(null)` convention: in free mode there
/// is no hint VALUE, so there is nothing for the decoder to apply.
@immutable
class ExpectedChordHint {
  const ExpectedChordHint._(this.label);

  /// The expected chord's display label, e.g. `C`, `Am`. Never empty: a null
  /// or blank label yields a null hint instead.
  final String label;

  /// Builds a hint for [label], or `null` when the hint is inadmissible —
  /// either because [mode] does not allow a prior at all
  /// ([RecognitionMode.free]) or because there is no label to expect.
  static ExpectedChordHint? forMode(RecognitionMode mode, String? label) {
    if (label == null || label.isEmpty) return null;
    return switch (mode) {
      RecognitionMode.free => null,
      RecognitionMode.guided => ExpectedChordHint._(label),
    };
  }

  @override
  bool operator ==(Object other) =>
      other is ExpectedChordHint && other.label == label;

  @override
  int get hashCode => label.hashCode;

  @override
  String toString() => 'ExpectedChordHint($label)';
}
