/// Compatibility shim (SDD Ch2 §10.2) — [Strum] and [StrumDirection] now live
/// in the shared musical domain; `BeatSlot` stayed in Live (it is a Live view
/// model). Import `package:strumsight/core/music/strum.dart` and, where the
/// beat counter is involved, `beat_slot.dart`. This file will be deleted in a
/// later round.
@Deprecated('Import package:strumsight/core/music/strum.dart')
library;

export '../../../core/music/strum.dart';
export 'beat_slot.dart';
