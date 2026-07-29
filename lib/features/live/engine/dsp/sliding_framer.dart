/// Compatibility shim (SDD Ch2 §10.2) — [SlidingFramer] is used by both the
/// Live pipeline and the Tuner engine, so it moved to the shared audio/DSP
/// boundary. Import `package:strumsight/core/audio/dsp/sliding_framer.dart`
/// instead; this file will be deleted in a later round.
@Deprecated('Import package:strumsight/core/audio/dsp/sliding_framer.dart')
library;

export '../../../../core/audio/dsp/sliding_framer.dart';
