/// Compatibility shim (SDD Ch2 §10.2) — [GuitarString] and [GuitarStrings] now
/// live in the shared musical domain. Import
/// `package:strumsight/core/music/guitar_strings.dart` instead; this file will
/// be deleted in a later round.
@Deprecated('Import package:strumsight/core/music/guitar_strings.dart')
library;

export '../../../core/music/guitar_strings.dart';
