import 'package:flutter/foundation.dart';

import '../../live/model/strum.dart';

const _d = StrumDirection.down;
const _u = StrumDirection.up;
const StrumDirection? _x = null; // rest

/// A named, ready-to-use 8-slot (eighth-note) strum pattern — the shortcuts the
/// Song Builder offers so you don't have to tap out a whole bar by hand. Down =
/// ↓, up = ↑, rest = silence on that eighth.
@immutable
class StrumPatternPreset {
  const StrumPatternPreset(this.name, this.pattern);

  final String name;

  /// Exactly 8 slots.
  final List<StrumDirection?> pattern;

  /// The staple strumming patterns most songs are built on.
  static const all = <StrumPatternPreset>[
    // Quarter-note downstrokes — the absolute-beginner strum.
    StrumPatternPreset('Down', [_d, _x, _d, _x, _d, _x, _d, _x]),
    // Straight eighths, alternating down/up.
    StrumPatternPreset('Eighths', [_d, _u, _d, _u, _d, _u, _d, _u]),
    // The classic folk/pop pattern: D — D U — U D U.
    StrumPatternPreset('Folk', [_d, _x, _d, _u, _x, _u, _d, _u]),
    // Ballad feel: D — — — D — D U.
    StrumPatternPreset('Ballad', [_d, _x, _x, _x, _d, _x, _d, _u]),
    // Reggae/ska off-beat up-strokes.
    StrumPatternPreset('Reggae', [_x, _u, _x, _u, _x, _u, _x, _u]),
    // Driving pop: D — D U D — D U.
    StrumPatternPreset('Pop', [_d, _x, _d, _u, _d, _x, _d, _u]),
  ];
}
