/// Compatibility shim (SDD Ch2 §10.2) — [ChordEvent] now lives in the shared
/// musical domain. Import `package:strumsight/core/music/chord_event.dart`
/// instead; this file will be deleted in a later round.
@Deprecated('Import package:strumsight/core/music/chord_event.dart')
library;

export '../../../core/music/chord_event.dart';
