/// Compatibility shim (SDD Ch2 §10.2) — [Tuning] and [Tunings] now live in the
/// shared musical domain. Import `package:strumsight/core/music/tuning.dart`
/// instead; this file will be deleted in a later round.
@Deprecated('Import package:strumsight/core/music/tuning.dart')
library;

export '../../../core/music/tuning.dart';
