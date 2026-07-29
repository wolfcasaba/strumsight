import 'guitar_strings.dart';

/// A named set of six strings (round 89 — alternate tunings, GuitarTuna-class
/// parity). The tuner's chips and nearest-string mapping follow the selected
/// tuning instead of hardwired standard.
class Tuning {
  const Tuning(this.id, this.strings);

  /// Stable id used for persistence and l10n lookup ('standard', 'dropD', …).
  final String id;

  /// Six strings, low → high.
  final List<GuitarString> strings;
}

class Tunings {
  Tunings._();

  static const standard = Tuning('standard', GuitarStrings.standard);

  /// Only the 6th string drops a whole step — the rock/folk workhorse.
  static const dropD = Tuning('dropD', [
    GuitarString('D2', 38),
    GuitarString('A2', 45),
    GuitarString('D3', 50),
    GuitarString('G3', 55),
    GuitarString('B3', 59),
    GuitarString('E4', 64),
  ]);

  /// Everything one semitone down (Eb standard), labelled in flats — that is
  /// how players name this tuning.
  static const halfStepDown = Tuning('halfStepDown', [
    GuitarString('Eb2', 39),
    GuitarString('Ab2', 44),
    GuitarString('Db3', 49),
    GuitarString('Gb3', 54),
    GuitarString('Bb3', 58),
    GuitarString('Eb4', 63),
  ]);

  /// The celtic/folk modal tuning.
  static const dadgad = Tuning('dadgad', [
    GuitarString('D2', 38),
    GuitarString('A2', 45),
    GuitarString('D3', 50),
    GuitarString('G3', 55),
    GuitarString('A3', 57),
    GuitarString('D4', 62),
  ]);

  static const List<Tuning> all = [standard, dropD, halfStepDown, dadgad];

  /// Resolve a persisted id; unknown ids fall back to standard (a renamed or
  /// removed preset must never crash the tuner).
  static Tuning byId(String id) =>
      all.firstWhere((t) => t.id == id, orElse: () => standard);
}
