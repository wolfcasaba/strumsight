import 'package:flutter/foundation.dart';

/// A recognised chord, e.g. C, Am, F#m, G.
///
/// v1 carries the display [label] only; root/quality decomposition (for
/// transpose/capo) can be added without touching consumers.
@immutable
class Chord {
  const Chord(this.label);

  /// Human display label ("C", "Am", "F#m").
  final String label;

  @override
  bool operator ==(Object other) => other is Chord && other.label == label;

  @override
  int get hashCode => label.hashCode;

  @override
  String toString() => label;
}
