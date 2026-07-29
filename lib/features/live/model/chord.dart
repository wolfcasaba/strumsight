/// Compatibility shim (SDD Ch2 §10.2) — [Chord] now lives in the shared
/// musical domain. Import `package:strumsight/core/music/chord.dart` instead;
/// this file exists so the migration could land without rewriting every
/// consumer in one commit, and will be deleted in a later round.
@Deprecated('Import package:strumsight/core/music/chord.dart')
library;

export '../../../core/music/chord.dart';
